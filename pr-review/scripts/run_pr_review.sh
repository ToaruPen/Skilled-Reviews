#!/usr/bin/env bash
set -euo pipefail

dry_run="0"
positional_args=()
while (($#)); do
  case "$1" in
    --dry-run)
      dry_run="1"
      shift
      ;;
    --)
      shift
      while (($#)); do
        positional_args+=("$1")
        shift
      done
      ;;
    --*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      positional_args+=("$1")
      shift
      ;;
  esac
done

if (( ${#positional_args[@]} < 1 || ${#positional_args[@]} > 2 )); then
  echo "Usage: $0 <scope-id> [run-id] [--dry-run]" >&2
  echo "Required env: SOT, TESTS" >&2
  echo "Optional env: RUN_ID, CONSTRAINTS, DIFF_SUMMARY_FILE, DIFF_STAT, INTENT, RISKY, ESTIMATION, CODE_REVIEW_FILE, SCHEMA_PATH, CODEX_BIN, MODEL, REASONING_EFFORT, VALIDATE, FORMAT_JSON, EXEC_TIMEOUT_SEC" >&2
  exit 1
fi

scope_id="${positional_args[0]}"
run_id="${positional_args[1]-}"
if [[ -z "$run_id" ]]; then
  run_id="${RUN_ID:-}"
fi

if [[ ! "$scope_id" =~ ^[A-Za-z0-9._-]+$ || "$scope_id" == "." || "$scope_id" == ".." ]]; then
  echo "Invalid scope-id: $scope_id (allowed: [A-Za-z0-9._-]+, not '.' or '..')" >&2
  exit 1
fi

sot="${SOT:-}"
tests="${TESTS:-}"
if [[ -z "$sot" || -z "$tests" ]]; then
  echo "SOT and TESTS must be set" >&2
  exit 1
fi

start_epoch=$(date +%s)
start_ts=$(date +"%Y-%m-%dT%H:%M:%S%z")
echo "Start: $start_ts" >&2

finish() {
  status=$?
  end_epoch=$(date +%s)
  end_ts=$(date +"%Y-%m-%dT%H:%M:%S%z")
  if [[ -n "${start_epoch:-}" ]]; then
    duration=$((end_epoch - start_epoch))
    echo "End: $end_ts (exit=${status}, duration=${duration}s)" >&2
  else
    echo "End: $end_ts (exit=${status})" >&2
  fi
}
trap finish EXIT

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  echo "Not in a git repository; cannot locate repo root." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skills_root="$(cd "$script_dir/../.." && pwd)"
ensure_script="${skills_root}/review-parallel/scripts/ensure_review_schemas.sh"
alt="${skills_root}/review-parallel (impl)/scripts/ensure_review_schemas.sh"
if [[ -x "$ensure_script" ]]; then
  : # ok
elif [[ -x "$alt" ]]; then
  ensure_script="$alt"
else
  echo "ensure_review_schemas.sh not found: $ensure_script (or $alt)" >&2
  exit 1
fi

constraints="${CONSTRAINTS:-none}"
intent="${INTENT:-}"
risky="${RISKY:-}"
estimation="${ESTIMATION:-}"
diff_summary_file="${DIFF_SUMMARY_FILE:-}"
diff_stat="${DIFF_STAT:-}"
code_review_file="${CODE_REVIEW_FILE:-}"

schema="${SCHEMA_PATH:-${repo_root}/.skilled-reviews/.reviews/schemas/review-v2.schema.json}"
codex_bin="${CODEX_BIN:-codex}"
model="${MODEL:-gpt-5.2}"
effort="${REASONING_EFFORT:-xhigh}"
validate="${VALIDATE:-1}"
exec_timeout_sec="${EXEC_TIMEOUT_SEC:-}"

if ! command -v "$codex_bin" >/dev/null 2>&1; then
  echo "codex not found: $codex_bin" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found" >&2
  exit 1
fi

timeout_bin=""
if [[ -n "$exec_timeout_sec" ]]; then
  if command -v timeout >/dev/null 2>&1; then
    timeout_bin="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_bin="gtimeout"
  else
    echo "EXEC_TIMEOUT_SEC set but no timeout/gtimeout found; running without timeout" >&2
  fi
fi

run_root="${repo_root}/.skilled-reviews/.reviews/reviewed_scopes/${scope_id}"
run_id_file="${run_root}/.current_run"
if [[ -z "$run_id" ]]; then
  if [[ -f "$run_id_file" ]]; then
    run_id="$(cat "$run_id_file")"
  else
    echo "run-id not provided and .current_run not found" >&2
    exit 1
  fi
fi

if [[ ! "$run_id" =~ ^[A-Za-z0-9._-]+$ || "$run_id" == "." || "$run_id" == ".." ]]; then
  echo "Invalid run-id: $run_id (allowed: [A-Za-z0-9._-]+, not '.' or '..')" >&2
  exit 1
fi

run_dir="${run_root}/${run_id}"
if [[ ! -d "$run_dir" ]]; then
  echo "Run directory not found: $run_dir" >&2
  exit 1
fi

if [[ -z "$code_review_file" ]]; then
  code_review_file="${run_dir}/code-review.json"
fi

out_dir="${run_dir}/aggregate"
out="${out_dir}/pr-review.json"

facets=(
  "correctness"
  "edge-cases"
  "security"
  "performance"
  "tests-observability"
  "design-consistency"
)
facets_csv="$(IFS=,; echo "${facets[*]}")"

missing_facets=()
for slug in "${facets[@]}"; do
  if [[ ! -f "${run_dir}/${slug}.json" ]]; then
    missing_facets+=("$slug")
  fi
done
if (( ${#missing_facets[@]} > 0 )); then
  printf 'Missing review fragments: %s\n' "${missing_facets[*]}" >&2
  exit 1
fi

if [[ -n "$diff_summary_file" ]]; then
  if [[ ! -f "$diff_summary_file" ]]; then
    if [[ -f "${repo_root}/${diff_summary_file}" ]]; then
      diff_summary_file="${repo_root}/${diff_summary_file}"
    else
      echo "Diff summary file not found: $diff_summary_file" >&2
      exit 1
    fi
  fi
  diff_stat="$(cat "$diff_summary_file")"
fi

if [[ -z "$diff_stat" ]]; then
  if [[ -z "$diff_summary_file" ]]; then
    candidate="${run_dir}/diff-summary.txt"
    if [[ -f "$candidate" ]]; then
      diff_stat="$(cat "$candidate")"
      diff_summary_file="$candidate"
    fi
  fi
fi

if [[ -z "$diff_stat" ]]; then
  echo "Diff summary required; set DIFF_SUMMARY_FILE or DIFF_STAT (prefer the review-parallel diff-summary.txt)" >&2
  exit 1
fi

if [[ "$dry_run" == "1" ]]; then
  echo "--dry-run: no files will be written" >&2
  echo "Plan:" >&2
  printf -- '- repo_root: %s\n' "$repo_root" >&2
  printf -- '- scope_id: %s\n' "$scope_id" >&2
  printf -- '- run_id: %s\n' "$run_id" >&2
  printf -- '- run_dir: %s\n' "$run_dir" >&2
  printf -- '- schema: %s\n' "$schema" >&2
  if [[ ! -f "$schema" ]]; then
    printf -- '  - note: schema will be generated by %s\n' "$ensure_script" >&2
  fi
  if [[ -n "$diff_summary_file" ]]; then
    printf -- '- diff_summary_file: %s\n' "$diff_summary_file" >&2
  fi
  printf -- '- out: %s\n' "$out" >&2
  printf -- '- validate: %s\n' "$validate" >&2
  printf -- '- codex_bin: %s\n' "$codex_bin" >&2
  printf -- '- model: %s\n' "$model" >&2
  printf -- '- reasoning_effort: %s\n' "$effort" >&2
  if [[ -n "$exec_timeout_sec" ]]; then
    printf -- '- exec_timeout_sec: %s\n' "$exec_timeout_sec" >&2
  fi
  exit 0
fi

"$ensure_script"

if [[ ! -f "$schema" ]]; then
  echo "Schema not found: $schema" >&2
  exit 1
fi

mkdir -p "$out_dir"

if [[ "$validate" != "0" ]]; then
  validate_script="${ensure_script%ensure_review_schemas.sh}validate_review_fragments.py"
  if [[ ! -f "$validate_script" ]]; then
    echo "validate_review_fragments.py not found: $validate_script" >&2
    exit 1
  fi

  format_arg=()
  if [[ "${FORMAT_JSON:-1}" != "0" ]]; then
    format_arg+=(--format)
  fi

  extra_args=()
  if [[ -f "$code_review_file" ]]; then
    extra_args+=(--extra-file "$code_review_file" --extra-slug "overall")
  fi

  (cd "$repo_root" && python3 "$validate_script" "$scope_id" "$run_id" --facets "$facets_csv" --schema "$schema" "${extra_args[@]}" "${format_arg[@]}")
fi

if [[ -z "$intent" ]]; then
  intent="- not provided"
fi

if [[ -z "$risky" ]]; then
  risky="- none"
fi

fragments="$(
  python3 - "$run_dir" "$facets_csv" "$code_review_file" <<'PY'
import json
import os
import sys

run_dir = sys.argv[1]
slugs = [s for s in sys.argv[2].split(",") if s]
code_review_path = sys.argv[3].strip() if len(sys.argv) > 3 else ""
if not slugs:
    print("No facets provided", file=sys.stderr)
    sys.exit(1)

data = []
missing = []
for slug in slugs:
    path = os.path.join(run_dir, f"{slug}.json")
    if not os.path.isfile(path):
        missing.append(slug)
        continue
    with open(path, "r", encoding="utf-8") as fh:
        data.append(json.load(fh))

if missing:
    print(f"Missing review fragments: {missing}", file=sys.stderr)
    sys.exit(1)

if code_review_path and os.path.isfile(code_review_path):
    try:
        with open(code_review_path, "r", encoding="utf-8") as fh:
            extra = json.load(fh)
    except Exception as exc:
        print(f"Invalid code-review JSON: {exc}", file=sys.stderr)
        sys.exit(1)
    required = {"facet", "facet_slug", "status", "findings", "uncertainty", "questions"}
    if not isinstance(extra, dict) or not required.issubset(extra.keys()):
        print("code-review JSON missing required keys", file=sys.stderr)
        sys.exit(1)
    data.append(extra)

print(json.dumps(data))
PY
)"

cmd=(
  "$codex_bin" exec
  --sandbox read-only
  -m "$model"
  -c "reasoning.effort=\"${effort}\""
  --output-last-message "$out"
  --output-schema "$schema"
  -
)
if [[ -n "$exec_timeout_sec" && -n "$timeout_bin" ]]; then
  cmd=("$timeout_bin" "$exec_timeout_sec" "${cmd[@]}")
fi

{
  cat <<'PROMPT'
You are the PR-level aggregator.

Rules:
- Do NOT re-review the full diff. Use the provided review fragments + diff summary only.
- Deduplicate and merge overlapping findings across facets.
- Preserve the original code_location from fragments; do not invent new locations.
- Keep findings actionable and discrete; ignore trivial style.

Priority (numeric 0-3):
- P0 (0): Drop everything to fix. Blocks release/ops/major usage. Universal (not input-dependent).
- P1 (1): Urgent. Should be fixed next cycle.
- P2 (2): Normal. Fix eventually.
- P3 (3): Low. Nice to have.

Status rules:
- Blocked if any finding has priority 0 or 1.
- Question if missing info prevents a correctness judgment (add to questions).
- Approved if findings=[] and questions=[].
- Approved with nits otherwise (only priority 2/3 findings).

overall_correctness mapping:
- Approved / Approved with nits => "patch is correct"
- Blocked / Question => "patch is incorrect"

Output requirements:
- facet must be "PR-level aggregate"
- facet_slug must be "aggregate"
- Output JSON only using the schema (no markdown fences, no extra prose).
PROMPT
  printf 'Inputs:\n'
  printf -- '- Diff summary:\nFiles:\n%s\n' "$diff_stat"
  printf 'Intent:\n%s\n' "$intent"
  printf 'Risky areas:\n%s\n' "$risky"
  printf -- '- Scope-id: %s\n' "$scope_id"
  printf -- '- SoT: %s\n' "$sot"
  if [[ -n "$estimation" ]]; then
    printf -- '- Estimation: %s\n' "$estimation"
  fi
  printf -- '- Tests: %s\n' "$tests"
  printf -- '- Constraints: %s\n' "$constraints"
  printf -- '- Review fragments: %s\n' "$fragments"
  printf 'Task: Integrate fragments into a single decision.\n'
} | "${cmd[@]}"

python3 - "$out" "$scope_id" <<'PY'
import json
import os
import sys

path = sys.argv[1]
scope_id = sys.argv[2]

with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

data["scope_id"] = scope_id

key_order = [
    "schema_version",
    "scope_id",
    "facet",
    "facet_slug",
    "status",
    "questions",
    "uncertainty",
    "findings",
    "overall_correctness",
    "overall_explanation",
    "overall_confidence_score",
]

ordered = {}
for key in key_order:
    if key in data:
        ordered[key] = data[key]
for key, value in data.items():
    if key not in ordered:
        ordered[key] = value

format_json = os.environ.get("FORMAT_JSON", "1") != "0"

with open(path, "w", encoding="utf-8") as fh:
    if format_json:
        json.dump(ordered, fh, ensure_ascii=False, indent=2)
    else:
        json.dump(ordered, fh, ensure_ascii=False)
    fh.write("\n")
PY

if [[ "$validate" != "0" ]]; then
  format_arg=()
  if [[ "${FORMAT_JSON:-1}" != "0" ]]; then
    format_arg+=(--format)
  fi
  (cd "$repo_root" && python3 "$validate_script" "$scope_id" "$run_id" --facets "" --schema "$schema" --extra-file "$out" --extra-slug "aggregate" "${format_arg[@]}")
fi
