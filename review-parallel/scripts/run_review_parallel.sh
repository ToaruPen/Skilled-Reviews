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
  echo "Optional env: RUN_ID, CONSTRAINTS, DIFF_FILE, DIFF_MODE, STRICT_STAGED, DIFF_SUMMARY_OUT, SCHEMA_PATH, CODEX_BIN, MODEL, REASONING_EFFORT, EXEC_TIMEOUT_SEC, VALIDATE, FORMAT_JSON" >&2
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
ensure_script="${script_dir}/ensure_review_schemas.sh"
if [[ ! -x "$ensure_script" ]]; then
  echo "ensure_review_schemas.sh not found: $ensure_script" >&2
  exit 1
fi

constraints="${CONSTRAINTS:-none}"
diff_file="${DIFF_FILE:-}"
diff_mode="${DIFF_MODE:-auto}"
strict_staged="${STRICT_STAGED:-0}"
diff_summary_out="${DIFF_SUMMARY_OUT:-}"
exec_timeout_sec="${EXEC_TIMEOUT_SEC:-}"
validate="${VALIDATE:-1}"
format_json="${FORMAT_JSON:-1}"

schema="${SCHEMA_PATH:-${repo_root}/.skilled-reviews/.reviews/schemas/review-fragment.schema.json}"
codex_bin="${CODEX_BIN:-codex}"
model="${MODEL:-gpt-5.2-codex}"
effort="${REASONING_EFFORT:-high}"
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

run_root="${repo_root}/.skilled-reviews/.reviews/reviewed_scopes/${scope_id}"
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
    if ! git -C "$repo_root" apply --stat "$diff_file" >/dev/null 2>&1; then
      echo "Failed to compute diff summary from diff file: $diff_file" >&2
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

  if [[ -n "$exec_timeout_sec" && -z "$timeout_bin" ]]; then
    echo "EXEC_TIMEOUT_SEC set but no timeout/gtimeout found; running without timeout" >&2
  fi

  echo "Plan:" >&2
  printf -- '- repo_root: %s\n' "$repo_root" >&2
  printf -- '- scope_id: %s\n' "$scope_id" >&2
  printf -- '- run_id: %s\n' "$run_id" >&2
  printf -- '- schema: %s\n' "$schema" >&2
  if [[ ! -f "$schema" ]]; then
    printf -- '  - note: schema will be generated by %s\n' "$ensure_script" >&2
  fi
  printf -- '- out_dir: %s\n' "$out_dir" >&2
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

if [[ -z "$diff_summary_out" ]]; then
  diff_summary_out="${out_dir}/diff-summary.txt"
fi
mkdir -p "$(dirname "$diff_summary_out")"
if ! git -C "$repo_root" apply --stat "$diff_file" > "$diff_summary_out" 2>/dev/null; then
  echo "Failed to compute diff summary from diff file: $diff_file" >&2
  exit 1
fi

# Facets are fixed in this script (slug:name).
facets=(
  "correctness:Correctness and logic"
  "edge-cases:Edge cases and error handling"
  "security:Security and data safety"
  "performance:Performance and resource use"
  "tests-observability:Tests and observability"
  "design-consistency:Design/consistency with project rules"
)

pids=()
slugs=()
outs=()

for f in "${facets[@]}"; do
  slug="${f%%:*}"
  name="${f#*:}"
  out="${out_dir}/${slug}.json"

  {
    cat <<'PROMPT'
Use review-parallel. Output JSON only using the schema.
PROMPT
    printf 'Facet: %s\n' "$name"
    printf 'Facet-Slug: %s\n' "$slug"
    printf 'SoT: %s\n' "$sot"
    printf 'Tests: %s\n' "$tests"
    printf 'Constraints: %s\n' "$constraints"
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
  } &

  pids+=("$!")
  slugs+=("$slug")
  outs+=("$out")
done

failures=()
for i in "${!pids[@]}"; do
  if ! wait "${pids[$i]}"; then
    failures+=("${slugs[$i]}")
    continue
  fi
  if [[ ! -s "${outs[$i]}" ]]; then
    failures+=("${slugs[$i]}")
  fi
done

if (( ${#failures[@]} > 0 )); then
  printf 'Failed facets: %s\n' "${failures[*]}" >&2
  exit 1
fi

if [[ "$validate" != "0" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found (required for VALIDATE=1)" >&2
    exit 1
  fi
  facets_csv="$(IFS=,; echo "${slugs[*]}")"
  validate_cmd=(python3 "$script_dir/validate_review_fragments.py" "$scope_id" "$run_id" --facets "$facets_csv")
  if [[ "$format_json" != "0" ]]; then
    validate_cmd+=(--format)
  fi
  (cd "$repo_root" && "${validate_cmd[@]}")
fi

tmp_run_file="${run_id_file}.tmp"
printf '%s' "$run_id" > "$tmp_run_file"
mv "$tmp_run_file" "$run_id_file"
