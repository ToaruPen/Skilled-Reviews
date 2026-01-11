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
  echo "Optional env: RUN_ID, CONSTRAINTS, DIFF_FILE, DIFF_MODE, STRICT_STAGED, SCHEMA_PATH, CODEX_BIN, MODEL, REASONING_EFFORT, EXEC_TIMEOUT_SEC, VALIDATE, FORMAT_JSON" >&2
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
diff_file="${DIFF_FILE:-}"
diff_mode="${DIFF_MODE:-auto}"
strict_staged="${STRICT_STAGED:-0}"
exec_timeout_sec="${EXEC_TIMEOUT_SEC:-}"
validate="${VALIDATE:-1}"
format_json="${FORMAT_JSON:-1}"

schema="${SCHEMA_PATH:-${repo_root}/docs/.reviews/schemas/review-fragment.schema.json}"
codex_bin="${CODEX_BIN:-codex}"
model="${MODEL:-gpt-5.2-codex}"
effort="${REASONING_EFFORT:-xhigh}"
if ! command -v "$codex_bin" >/dev/null 2>&1; then
  echo "codex not found: $codex_bin" >&2
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
    candidate="$(cat "$run_id_file")"
    if [[ "$candidate" =~ ^[A-Za-z0-9._-]+$ && "$candidate" != "." && "$candidate" != ".." ]]; then
      run_id="$candidate"
    else
      echo "Invalid .current_run detected; generating a new run-id" >&2
      run_id=""
    fi
  fi
  if [[ -z "$run_id" ]]; then
    run_id="$(date +"%Y%m%d_%H%M%S")"
  fi
fi

if [[ ! "$run_id" =~ ^[A-Za-z0-9._-]+$ || "$run_id" == "." || "$run_id" == ".." ]]; then
  echo "Invalid run-id: $run_id (allowed: [A-Za-z0-9._-]+, not '.' or '..')" >&2
  exit 1
fi

out_dir="${run_root}/${run_id}"
printf 'Run ID: %s\n' "$run_id" >&2

out="${out_dir}/code-review.json"

if [[ "$dry_run" == "1" ]]; then
  echo "--dry-run: no files will be written" >&2

  if [[ -n "$diff_file" ]]; then
    if [[ ! -f "$diff_file" ]]; then
      echo "Diff file not found: $diff_file" >&2
      exit 1
    fi
    if [[ ! -s "$diff_file" ]]; then
      echo "Diff is empty: $diff_file" >&2
      exit 1
    fi
  else
    diff_source=""
    case "$diff_mode" in
      staged)
        if git -C "$repo_root" diff --quiet --staged; then
          echo "Diff is empty (staged)" >&2
          exit 1
        fi
        diff_source="staged"
        ;;
      worktree)
        if git -C "$repo_root" diff --quiet; then
          echo "Diff is empty (worktree)" >&2
          exit 1
        fi
        diff_source="worktree"
        ;;
      auto|"")
        if git -C "$repo_root" diff --quiet --staged; then
          if [[ "$strict_staged" == "1" ]]; then
            echo "STRICT_STAGED=1 and staged diff is empty" >&2
            exit 1
          fi
          if git -C "$repo_root" diff --quiet; then
            echo "Diff is empty (staged and worktree)" >&2
            exit 1
          fi
          diff_source="worktree"
        else
          diff_source="staged"
        fi
        ;;
      *)
        echo "Invalid DIFF_MODE: $diff_mode (use staged|worktree|auto)" >&2
        exit 1
        ;;
    esac
    printf 'Diff source: %s\n' "$diff_source" >&2
  fi

  echo "Plan:" >&2
  printf -- '- repo_root: %s\n' "$repo_root" >&2
  printf -- '- scope_id: %s\n' "$scope_id" >&2
  printf -- '- run_id: %s\n' "$run_id" >&2
  printf -- '- schema: %s\n' "$schema" >&2
  if [[ ! -f "$schema" ]]; then
    printf -- '  - note: schema will be generated by %s\n' "$ensure_script" >&2
  fi
  printf -- '- out: %s\n' "$out" >&2
  printf -- '- diff_mode: %s\n' "$diff_mode" >&2
  if [[ -n "$diff_file" ]]; then
    printf -- '- diff_file: %s\n' "$diff_file" >&2
  fi
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

mkdir -p "$run_root"
mkdir -p "$out_dir"

tmp_diff=""
cleanup() {
  status=$?
  end_epoch=$(date +%s)
  end_ts=$(date +"%Y-%m-%dT%H:%M:%S%z")
  if [[ -n "${start_epoch:-}" ]]; then
    duration=$((end_epoch - start_epoch))
    echo "End: $end_ts (exit=${status}, duration=${duration}s)" >&2
  else
    echo "End: $end_ts (exit=${status})" >&2
  fi
  if [[ -n "$tmp_diff" && -f "$tmp_diff" ]]; then
    rm -f "$tmp_diff"
  fi
}
trap cleanup EXIT

diff_source=""
if [[ -n "$diff_file" ]]; then
  if [[ ! -f "$diff_file" ]]; then
    echo "Diff file not found: $diff_file" >&2
    exit 1
  fi
else
  tmp_diff="$(mktemp)"
  case "$diff_mode" in
    staged)
      git -C "$repo_root" diff --no-color --staged > "$tmp_diff"
      diff_source="staged"
      ;;
    worktree)
      git -C "$repo_root" diff --no-color > "$tmp_diff"
      diff_source="worktree"
      ;;
    auto|"")
      git -C "$repo_root" diff --no-color --staged > "$tmp_diff"
      if [[ -s "$tmp_diff" ]]; then
        diff_source="staged"
      else
        if [[ "$strict_staged" == "1" ]]; then
          echo "STRICT_STAGED=1 and staged diff is empty" >&2
          exit 1
        fi
        git -C "$repo_root" diff --no-color > "$tmp_diff"
        diff_source="worktree"
      fi
      ;;
    *)
      echo "Invalid DIFF_MODE: $diff_mode (use staged|worktree|auto)" >&2
      exit 1
      ;;
  esac
  diff_file="$tmp_diff"
fi

if [[ -n "$diff_source" ]]; then
  echo "Diff source: $diff_source" >&2
fi

if [[ ! -s "$diff_file" ]]; then
  echo "Diff is empty: $diff_file" >&2
  exit 1
fi

{
  cat <<'PROMPT'
Use code-review. Output JSON only using the schema.
Rules:
- facet must be "Overall review (code-review)"
- facet_slug must be "overall"
- status must be one of: Approved, Approved with nits, Blocked, Question
- findings must be an array; use severity: blocker|major|minor|nit
- if no findings, use []
- if information is missing, set status Question and add to questions
PROMPT
  printf 'Facet: Overall review (code-review)\n'
  printf 'Facet-Slug: overall\n'
  printf 'SoT: %s\n' "$sot"
  printf 'Tests: %s\n' "$tests"
  printf 'Constraints: %s\n' "$constraints"
  printf 'Expectations: review-only; read-only; do not edit\n'
  printf 'Diff:\n'
  cat "$diff_file"
} | {
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
  "${cmd[@]}"
}

if [[ "$validate" != "0" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found (required for VALIDATE=1)" >&2
    exit 1
  fi
  (cd "$repo_root" && python3 - "$out" "$schema" "$format_json" <<'PY'
import json
import os
import sys

path = sys.argv[1]
schema_path = sys.argv[2]
format_json = sys.argv[3] != "0"

STATUS_ALLOWED = {"Approved", "Approved with nits", "Blocked", "Question"}
SEVERITY_ALLOWED = {"blocker", "major", "minor", "nit"}
REQUIRED = {"facet", "facet_slug", "status", "findings", "uncertainty", "questions"}
F_REQUIRED = {"severity", "issue", "evidence", "impact", "fix_idea"}

KEY_ORDER = ["facet", "facet_slug", "status", "findings", "uncertainty", "questions"]
F_KEY_ORDER = ["severity", "issue", "evidence", "impact", "fix_idea"]


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


def normalize_fragment(obj: dict) -> dict:
    ordered: dict = {}
    for key in KEY_ORDER:
        if key in obj:
            ordered[key] = obj[key]

    findings = ordered.get("findings")
    if isinstance(findings, list):
        normalized_findings = []
        for item in findings:
            if not isinstance(item, dict):
                normalized_findings.append(item)
                continue
            f_ordered: dict = {}
            for key in F_KEY_ORDER:
                if key in item:
                    f_ordered[key] = item[key]
            for key, value in item.items():
                if key not in f_ordered:
                    f_ordered[key] = value
            normalized_findings.append(f_ordered)
        ordered["findings"] = normalized_findings

    for key, value in obj.items():
        if key not in ordered:
            ordered[key] = value

    return ordered


def validate_fragment(obj, expected_slug):
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

    if facet != "Overall review (code-review)":
        errors.append('facet must be "Overall review (code-review)"')
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

try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception as exc:
    print(f"invalid JSON: {exc}", file=sys.stderr)
    raise SystemExit(1)

errors = validate_fragment(data, "overall")
if errors:
    print("invalid fragment:", file=sys.stderr)
    for err in errors:
        print(f"  - {err}", file=sys.stderr)
    raise SystemExit(1)

if format_json:
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(normalize_fragment(data), fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(tmp, path)
PY
)
fi

tmp_run_file="${run_id_file}.tmp"
printf '%s' "$run_id" > "$tmp_run_file"
mv "$tmp_run_file" "$run_id_file"
