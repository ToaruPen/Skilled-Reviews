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
  echo "Required env: SOT, ESTIMATION_FILE" >&2
  echo "Optional env: RUN_ID, PLAN_FILE, REVIEW_FILE, CLARIFICATIONS, CONSTRAINTS, POLICY_FILE, APPLY, ALLOW_LARGE_PATCH, CODEX_BIN, MODEL, REASONING_EFFORT, EXEC_TIMEOUT_SEC" >&2
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
estimation_file="${ESTIMATION_FILE:-}"
if [[ -z "$sot" || -z "$estimation_file" ]]; then
  echo "SOT and ESTIMATION_FILE must be set" >&2
  exit 1
fi

plan_file="${PLAN_FILE:-}"
review_file="${REVIEW_FILE:-}"
clarifications="${CLARIFICATIONS:-}"
constraints="${CONSTRAINTS:-none}"
policy_file="${POLICY_FILE:-}"

apply_changes="${APPLY:-1}"
allow_large_patch="${ALLOW_LARGE_PATCH:-0}"
exec_timeout_sec="${EXEC_TIMEOUT_SEC:-}"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  echo "Not in a git repository; cannot locate repo root." >&2
  exit 1
fi

if [[ "$estimation_file" != /* ]]; then
  estimation_file="${repo_root}/${estimation_file}"
fi
if [[ ! -f "$estimation_file" || ! -s "$estimation_file" ]]; then
  echo "Estimation file not found or empty: $estimation_file" >&2
  exit 1
fi

if [[ -n "$plan_file" ]]; then
  if [[ "$plan_file" != /* ]]; then
    plan_file="${repo_root}/${plan_file}"
  fi
  if [[ ! -f "$plan_file" || ! -s "$plan_file" ]]; then
    echo "Plan file not found or empty: $plan_file" >&2
    exit 1
  fi
fi

if [[ -n "$review_file" ]]; then
  if [[ "$review_file" != /* ]]; then
    review_file="${repo_root}/${review_file}"
  fi
  if [[ ! -f "$review_file" || ! -s "$review_file" ]]; then
    echo "Review file not found or empty: $review_file" >&2
    exit 1
  fi
fi

if [[ -z "$policy_file" ]]; then
  policy_file="${repo_root}/.skilled-reviews/.implementation/impl-guardrails.toml"
elif [[ "$policy_file" != /* ]]; then
  policy_file="${repo_root}/${policy_file}"
fi
if [[ ! -f "$policy_file" || ! -s "$policy_file" ]]; then
  echo "Guardrails policy not found or empty: $policy_file" >&2
  echo "Expected a repo-local policy (gitignored) at: ${repo_root}/.skilled-reviews/.implementation/impl-guardrails.toml" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="${script_dir}/validate_implementation_patch.py"
if [[ ! -f "$validator" ]]; then
  echo "Validator script not found: $validator" >&2
  exit 1
fi

review_extractor="${script_dir}/extract_review_feedback.py"
if [[ -n "$review_file" && ! -f "$review_extractor" ]]; then
  echo "Review feedback extractor not found: $review_extractor" >&2
  exit 1
fi

codex_bin="${CODEX_BIN:-codex}"
model="${MODEL:-gpt-5.2-codex}"
effort="${REASONING_EFFORT:-high}"
if ! command -v "$codex_bin" >/dev/null 2>&1; then
  echo "codex not found: $codex_bin" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found (required for patch extraction/validation)" >&2
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

# Safety: avoid applying onto a dirty index or worktree (untracked files are OK).
if ! git -C "$repo_root" diff --quiet; then
  echo "Unstaged changes detected; aborting to avoid mixing scopes." >&2
  exit 1
fi
if ! git -C "$repo_root" diff --cached --quiet; then
  echo "Staged changes detected; aborting to avoid mixing scopes." >&2
  exit 1
fi

if [[ -z "$run_id" ]]; then
  run_id="$(date +"%Y%m%d_%H%M%S")"
fi
if [[ ! "$run_id" =~ ^[A-Za-z0-9._-]+$ || "$run_id" == "." || "$run_id" == ".." ]]; then
  echo "Invalid run-id: $run_id (allowed: [A-Za-z0-9._-]+, not '.' or '..')" >&2
  exit 1
fi

run_dir="${repo_root}/.skilled-reviews/.implementation/impl-runs/${scope_id}/${run_id}"
raw_out="${run_dir}/raw.txt"
patch_out="${run_dir}/patch.diff"

echo "Repo: $repo_root" >&2
echo "Scope ID: $scope_id" >&2
echo "Run ID: $run_id" >&2
echo "Policy: $policy_file" >&2
echo "Raw out: $raw_out" >&2
echo "Patch out: $patch_out" >&2
printf -- '- model: %s\n' "$model" >&2
printf -- '- reasoning_effort: %s\n' "$effort" >&2

if [[ "$dry_run" == "1" ]]; then
  echo "--dry-run: prerequisites OK (no patch will be generated/applied)" >&2
  exit 0
fi

mkdir -p "$run_dir"

review_feedback=""
if [[ -n "$review_file" ]]; then
  review_feedback="$(python3 "$review_extractor" "$review_file")"
  if ! grep -q '[^[:space:]]' <<<"$review_feedback"; then
    echo "Review feedback extractor returned empty output for: $review_file" >&2
    echo "Fail-closed: REVIEW_FILE is set but extracted guidance is empty." >&2
    exit 1
  fi
fi

{
  cat <<'PROMPT'
You are an implementation agent operating in a git repository.

You MUST output exactly one of the following:
1) A unified diff patch starting with: "diff --git ..." (no markdown, no explanations)
2) If requirements are missing/ambiguous: output
   "QUESTION:"
   "- <question 1>"
   "- <question 2>"
   and nothing else.

Patch format requirements:
- The patch MUST be accepted by: `git apply --check`
- For new files, include a `new file mode 100644` header (git-style patch).
- Do not repeat/duplicate diff blocks; output each file diff once.

Hard rules (v1, fail-closed by wrapper checks):
- No renames, copies, deletes, mode changes.
- No binary patches, symlinks, or submodules.
- Keep changes minimal and aligned with SoT + estimation.
- Follow repository rules (AGENTS.md/CONTRIBUTING/docs).
- Do not modify documentation unless explicitly required AND allowed by the guardrails policy.

Review follow-up rules (only when a review file is provided in Context):
- You MUST read the review JSON file itself (review-v2) at the provided path.
- Treat the review JSON as the source of truth. The parsed feedback is convenience-only.
- You MUST fix all findings with priority 0 or 1 (P0/P1). Do not ignore or defer them.
- Only address P2/P3 if required to fix P0/P1 or trivial and clearly safe.
- If any P0/P1 cannot be fixed within guardrails/constraints or due to missing information, output QUESTION explaining why.

Context:
PROMPT
  printf 'SoT: %s\n' "$sot"
  printf 'Estimation file: %s\n' "$estimation_file"
	  if [[ -n "$plan_file" ]]; then
	    printf 'Plan file: %s\n' "$plan_file"
	  fi
	  if [[ -n "$review_file" ]]; then
	    printf 'Review file (review-v2 JSON; MUST READ): %s\n' "$review_file"
	    printf 'Review feedback summary (parsed; convenience only):\n%s\n' "$review_feedback"
	    printf 'Note: review JSON is not inlined; read the file at the path above.\n'
	  fi
	  if [[ -n "$clarifications" ]]; then
	    printf 'Clarifications:\n%s\n' "$clarifications"
	  fi
  printf 'Constraints: %s\n' "$constraints"
  printf 'Guardrails policy file: %s\n' "$policy_file"
  printf 'Guardrails policy (read-only):\n'
  cat "$policy_file"
  cat <<'PROMPT'

Task:
- Read the estimation file and any referenced SoT/specs.
- Implement the described scope.
- Output a unified diff patch only.
PROMPT
} | {
  cmd=(
    "$codex_bin" exec
    --sandbox read-only
    -C "$repo_root"
    -m "$model"
    -c "reasoning.effort=\"${effort}\""
    --output-last-message "$raw_out"
    -
  )
  if [[ -n "$exec_timeout_sec" && -n "$timeout_bin" ]]; then
    cmd=("$timeout_bin" "$exec_timeout_sec" "${cmd[@]}")
  fi
  "${cmd[@]}"
}

if [[ ! -s "$raw_out" ]]; then
  echo "codex output is empty: $raw_out" >&2
  exit 1
fi

first_non_empty="$(grep -m1 -v '^[[:space:]]*$' "$raw_out" || true)"
if [[ -z "$first_non_empty" ]]; then
  echo "codex output contains only whitespace: $raw_out" >&2
  exit 1
fi

if [[ "$first_non_empty" == QUESTION:* ]]; then
  echo "Model stopped with QUESTION (no patch applied):" >&2
  cat "$raw_out" >&2
  exit 2
fi

python3 - "$raw_out" "$patch_out" <<'PY'
import sys

raw_path = sys.argv[1]
patch_path = sys.argv[2]

with open(raw_path, "r", encoding="utf-8", errors="replace") as fh:
    lines = fh.read().splitlines(True)

start = None
end = None
for i, line in enumerate(lines):
    if line.startswith("diff --git "):
        start = i
        break

if start is None:
    sys.exit(0)

for j in range(start, len(lines)):
    if lines[j].startswith("```"):
        end = j
        break

patch_lines = lines[start:] if end is None else lines[start:end]
if patch_lines and not patch_lines[-1].endswith("\n"):
    patch_lines[-1] += "\n"
with open(patch_path, "w", encoding="utf-8") as out:
    out.writelines(patch_lines)
PY

if [[ ! -s "$patch_out" ]]; then
  echo "Model output did not contain a unified diff; treating as QUESTION and stopping (no patch applied)." >&2
  cat "$raw_out" >&2
  exit 2
fi

first_patch_line="$(grep -m1 -v '^[[:space:]]*$' "$patch_out" || true)"
if [[ "$first_patch_line" != diff\ --git\ * ]]; then
  echo "Extracted patch is not a unified diff; stopping (no patch applied)." >&2
  cat "$raw_out" >&2
  exit 2
fi

validate_cmd=(python3 "$validator" --repo-root "$repo_root" --patch "$patch_out" --policy "$policy_file")
if [[ "$allow_large_patch" == "1" ]]; then
  validate_cmd+=(--allow-large-patch)
fi
"${validate_cmd[@]}"

if [[ "$apply_changes" == "0" ]]; then
  echo "APPLY=0: patch generated and validated, but not applied." >&2
  exit 0
fi

git -C "$repo_root" apply "$patch_out"
echo "Applied patch: $patch_out" >&2
