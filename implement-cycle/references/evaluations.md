# Skill Evaluations (Lightweight)

These are manual, copy/paste-friendly self-checks for maintaining the `impl` / review-related skills and scripts.

Notes:
- Prefer `--dry-run` for fast safety checks (no file writes when inputs are valid).
- Convention: `--dry-run` exits `0` when the run is *ready* (preflight passes) and exits `1` when inputs/env are insufficient.
- `scope-id` / `run-id` must match `^[A-Za-z0-9._-]+$` and must not be `.` or `..` (no `/`).
- You can set `CODEX_BIN=true` for `--dry-run` cases to avoid requiring a working `codex` binary.

## Evaluation 1: review-parallel dry-run (staged preferred)

Goal: Confirm `DIFF_MODE=auto` prefers staged changes and returns `exit 0`.

```bash
tmp="$(mktemp -d)"
cd "$tmp"
git init
git config user.email test@example.com
git config user.name test

echo "hello" > a.txt
git add a.txt
git commit -m "init"

echo "world" >> a.txt
git add a.txt  # staged diff exists

SOT='- none' TESTS='- not run' CODEX_BIN=true \
  "$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" \
  demo-scope --dry-run
echo "exit=$?"
```

Expected:
- Output includes `Diff source: staged`
- `exit=0`

## Evaluation 2: identifier validation rejects slash

Goal: Confirm `/` is rejected in `scope-id` (and fails fast with `exit 1`).

```bash
SOT='- none' TESTS='- not run' CODEX_BIN=true \
  "$HOME/.codex/skills/code-review (impl)/scripts/run_code_review.sh" \
  'bad/scope' --dry-run
echo "exit=$?"
```

Expected:
- Output includes `Invalid scope-id`
- `exit=1`

## Evaluation 3: pr-review dry-run (preflight success with minimal run_dir)

Goal: Confirm `pr-review` can reach the plan stage (facet files + diff summary present) and returns `exit 0`.

```bash
tmp="$(mktemp -d)"
cd "$tmp"
git init

scope_id="demo-scope"
run_id="testrun"
run_dir="docs/.reviews/reviewed_scopes/${scope_id}/${run_id}"

mkdir -p "$run_dir"
for slug in correctness edge-cases security performance tests-observability design-consistency; do
  printf '{}' > "${run_dir}/${slug}.json"
done
printf '1 file changed, 1 insertion(+)\n' > "${run_dir}/diff-summary.txt"

SOT='- none' TESTS='- not run' CODEX_BIN=true DIFF_SUMMARY_FILE="${run_dir}/diff-summary.txt" \
  "$HOME/.codex/skills/pr-review (impl)/scripts/run_pr_review.sh" \
  "$scope_id" "$run_id" --dry-run
echo "exit=$?"
```

Expected:
- Output includes `Plan:`
- `exit=0`

