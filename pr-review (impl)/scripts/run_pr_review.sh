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
ensure_script="${skills_root}/review-parallel (impl)/scripts/ensure_review_schemas.sh"
if [[ ! -x "$ensure_script" ]]; then
  echo "ensure_review_schemas.sh not found: $ensure_script" >&2
  exit 1
fi

constraints="${CONSTRAINTS:-none}"
intent="${INTENT:-}"
risky="${RISKY:-}"
estimation="${ESTIMATION:-}"
diff_summary_file="${DIFF_SUMMARY_FILE:-}"
diff_stat="${DIFF_STAT:-}"
code_review_file="${CODE_REVIEW_FILE:-}"

schema="${SCHEMA_PATH:-${repo_root}/docs/.reviews/schemas/pr-review.schema.json}"
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

run_root="${repo_root}/docs/.reviews/reviewed_scopes/${scope_id}"
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
  echo "Diff summary required; set DIFF_SUMMARY_FILE or DIFF_STAT (prefer the 7-1 diff-summary.txt)" >&2
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
  fragment_schema="${repo_root}/docs/.reviews/schemas/review-fragment.schema.json"
  if [[ ! -f "$fragment_schema" ]]; then
    echo "Fragment schema not found: $fragment_schema" >&2
    exit 1
  fi

  extra_file=""
  if [[ -f "$code_review_file" ]]; then
    extra_file="$code_review_file"
  fi

  (cd "$repo_root" && python3 - "$fragment_schema" "$run_dir" "$facets_csv" "$extra_file" <<'PY'
import json
import os
import sys

schema_path = sys.argv[1]
run_dir = sys.argv[2]
slugs = [s for s in sys.argv[3].split(",") if s]
extra_file = sys.argv[4].strip()

STATUS_ALLOWED = {"Approved", "Approved with nits", "Blocked", "Question"}
SEVERITY_ALLOWED = {"blocker", "major", "minor", "nit"}
REQUIRED = {"facet", "facet_slug", "status", "findings", "uncertainty", "questions"}
F_REQUIRED = {"severity", "issue", "evidence", "impact", "fix_idea"}


def validate_schema(schema):
    errors = []
    if not isinstance(schema, dict):
        return ["schema root is not an object"]
    if schema.get("type") != "object":
        errors.append("schema.type must be 'object'")
    if schema.get("additionalProperties") is not False:
        errors.append("schema.additionalProperties must be false")
    required = schema.get("required")
    if not isinstance(required, list) or set(required) != REQUIRED:
        errors.append(f"schema.required must be {sorted(REQUIRED)}")
    props = schema.get("properties")
    if not isinstance(props, dict):
        errors.append("schema.properties must be an object")
        return errors
    status = props.get("status")
    status_enum = status.get("enum") if isinstance(status, dict) else None
    if not isinstance(status_enum, list) or set(status_enum) != STATUS_ALLOWED:
        errors.append(f"schema.properties.status.enum must be {sorted(STATUS_ALLOWED)}")
    findings = props.get("findings")
    if not isinstance(findings, dict) or findings.get("type") != "array":
        errors.append("schema.properties.findings must be an array")
        return errors
    items = findings.get("items")
    if not isinstance(items, dict) or items.get("type") != "object":
        errors.append("schema.properties.findings.items must be an object schema")
        return errors
    if items.get("additionalProperties") is not False:
        errors.append("schema.properties.findings.items.additionalProperties must be false")
    f_required = items.get("required")
    if not isinstance(f_required, list) or set(f_required) != F_REQUIRED:
        errors.append(f"schema.properties.findings.items.required must be {sorted(F_REQUIRED)}")
    item_props = items.get("properties")
    if not isinstance(item_props, dict):
        errors.append("schema.properties.findings.items.properties must be an object")
        return errors
    severity = item_props.get("severity")
    severity_enum = severity.get("enum") if isinstance(severity, dict) else None
    if not isinstance(severity_enum, list) or set(severity_enum) != SEVERITY_ALLOWED:
        errors.append(
            f"schema.properties.findings.items.properties.severity.enum must be {sorted(SEVERITY_ALLOWED)}"
        )
    return errors


def validate_fragment(obj, expected_slug, expected_facet=None):
    errors = []
    if not isinstance(obj, dict):
        return ["root is not an object"]

    missing = REQUIRED - set(obj.keys())
    if missing:
        errors.append(f"missing keys: {sorted(missing)}")
    extra = set(obj.keys()) - REQUIRED
    if extra:
        errors.append(f"unexpected keys: {sorted(extra)}")

    facet = obj.get("facet")
    facet_slug = obj.get("facet_slug")
    status = obj.get("status")
    findings = obj.get("findings")
    uncertainty = obj.get("uncertainty")
    questions = obj.get("questions")

    if expected_facet is not None and facet != expected_facet:
        errors.append(f'facet must be \"{expected_facet}\"')
    if not isinstance(facet, str) or not facet:
        errors.append("facet must be a non-empty string")
    if facet_slug != expected_slug:
        errors.append(f"facet_slug mismatch: expected {expected_slug}, got {facet_slug}")
    if status not in STATUS_ALLOWED:
        errors.append(f"status must be one of {sorted(STATUS_ALLOWED)}")

    if not isinstance(findings, list):
        errors.append("findings must be an array")
    else:
        for idx, item in enumerate(findings):
            if not isinstance(item, dict):
                errors.append(f"findings[{idx}] is not an object")
                continue
            f_missing = F_REQUIRED - set(item.keys())
            if f_missing:
                errors.append(f"findings[{idx}] missing keys: {sorted(f_missing)}")
            f_extra = set(item.keys()) - F_REQUIRED
            if f_extra:
                errors.append(f"findings[{idx}] unexpected keys: {sorted(f_extra)}")
            severity = item.get("severity")
            if severity not in SEVERITY_ALLOWED:
                errors.append(
                    f"findings[{idx}].severity must be one of {sorted(SEVERITY_ALLOWED)}"
                )
            for key in ("issue", "evidence", "impact", "fix_idea"):
                if key in item and not isinstance(item[key], str):
                    errors.append(f"findings[{idx}].{key} must be a string")

    if not isinstance(uncertainty, list) or any(not isinstance(x, str) for x in uncertainty):
        errors.append("uncertainty must be an array of strings")
    if not isinstance(questions, list) or any(not isinstance(x, str) for x in questions):
        errors.append("questions must be an array of strings")

    return errors


try:
    with open(schema_path, "r", encoding="utf-8") as fh:
        schema_doc = json.load(fh)
except Exception as exc:
    print(f"schema invalid JSON: {exc}", file=sys.stderr)
    raise SystemExit(1)

schema_errors = validate_schema(schema_doc)
if schema_errors:
    print("schema mismatch (update schema generator and/or validator):", file=sys.stderr)
    for err in schema_errors:
        print(f"  - {err}", file=sys.stderr)
    raise SystemExit(1)

invalid = []
for slug in slugs:
    path = os.path.join(run_dir, f"{slug}.json")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as exc:
        invalid.append((slug, [f"invalid JSON: {exc}"]))
        continue
    errors = validate_fragment(data, slug)
    if errors:
        invalid.append((slug, errors))

if extra_file:
    try:
        with open(extra_file, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as exc:
        invalid.append(("overall", [f"invalid JSON: {exc}"]))
    else:
        errors = validate_fragment(
            data, "overall", expected_facet="Overall review (code-review)"
        )
        if errors:
            invalid.append(("overall", errors))

if invalid:
    for slug, errors in invalid:
        print(f"invalid fragment '{slug}':", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
    raise SystemExit(1)

print(f"OK: {len(slugs)} fragments valid")
PY
)
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
  printf 'You are the PR-level aggregator.\n'
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
  printf 'Task: Integrate fragments into a single decision. Do not re-review the diff. Deduplicate, resolve conflicts, prioritize, and decide readiness.\n'
  printf 'Output JSON only (no markdown) using the JSON Output Schema. The output must include scope_id: %s.\n' "$scope_id"
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
    "scope_id",
    "status",
    "top_risks",
    "required_fixes",
    "optional_nits",
    "assumptions",
    "questions",
    "facet_coverage",
]

ordered = {}
for key in key_order:
    if key in data:
        ordered[key] = data[key]
for key, value in data.items():
    if key not in ordered:
        ordered[key] = value

required_fixes = ordered.get("required_fixes")
if isinstance(required_fixes, list):
    normalized = []
    for item in required_fixes:
        if not isinstance(item, dict):
            normalized.append(item)
            continue
        fix = {}
        for k in ("issue", "evidence", "fix_idea"):
            if k in item:
                fix[k] = item[k]
        for k, v in item.items():
            if k not in fix:
                fix[k] = v
        normalized.append(fix)
    ordered["required_fixes"] = normalized

facet_coverage = ordered.get("facet_coverage")
if isinstance(facet_coverage, list):
    normalized = []
    for item in facet_coverage:
        if not isinstance(item, dict):
            normalized.append(item)
            continue
        cov = {}
        for k in ("facet_slug", "status"):
            if k in item:
                cov[k] = item[k]
        for k, v in item.items():
            if k not in cov:
                cov[k] = v
        normalized.append(cov)
    ordered["facet_coverage"] = normalized

format_json = os.environ.get("FORMAT_JSON", "1") != "0"

with open(path, "w", encoding="utf-8") as fh:
    if format_json:
        json.dump(ordered, fh, ensure_ascii=False, indent=2)
    else:
        json.dump(ordered, fh, ensure_ascii=False)
    fh.write("\n")
PY
