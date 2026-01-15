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
  "$HOME/.codex/skills/review-parallel/scripts/run_review_parallel.sh" \
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
  "$HOME/.codex/skills/code-review/scripts/run_code_review.sh" \
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
run_dir=".skilled-reviews/.reviews/reviewed_scopes/${scope_id}/${run_id}"

mkdir -p "$run_dir"
for slug in correctness edge-cases security performance tests-observability design-consistency; do
  printf '{}' > "${run_dir}/${slug}.json"
done
printf '1 file changed, 1 insertion(+)\n' > "${run_dir}/diff-summary.txt"

SOT='- none' TESTS='- not run' CODEX_BIN=true DIFF_SUMMARY_FILE="${run_dir}/diff-summary.txt" \
  "$HOME/.codex/skills/pr-review/scripts/run_pr_review.sh" \
  "$scope_id" "$run_id" --dry-run
echo "exit=$?"
```

Expected:
- Output includes `Plan:`
- `exit=0`

## Evaluation 4: implementation dry-run (preflight only; no codex required)

Goal: Confirm `implementation` preflight works and returns `exit 0` without requiring a real `codex` binary.

```bash
tmp="$(mktemp -d)"
cd "$tmp"
git init
git config user.email test@example.com
git config user.name test

echo "hello" > a.txt
git add a.txt
git commit -m "init"

mkdir -p .skilled-reviews/.implementation
cat > .skilled-reviews/.implementation/impl-guardrails.toml <<'TOML'
write_allow = [
  "hello.txt",
]

write_deny = [
  ".skilled-reviews/**",
  ".git/**",
]
TOML

mkdir -p .skilled-reviews/.estimation
cat > .skilled-reviews/.estimation/impl_smoke.md <<'MD'
# impl smoke

- Create `hello.txt` with `hello`.
MD

SOT='- none' ESTIMATION_FILE='.skilled-reviews/.estimation/impl_smoke.md' CODEX_BIN=true \
  "$HOME/.codex/skills/implementation/scripts/run_implementation.sh" \
  demo-scope --dry-run
echo "exit=$?"

test ! -e .skilled-reviews/.implementation/impl-runs
```

Expected:
- Output includes `--dry-run: prerequisites OK`
- `exit=0`

## Evaluation 5: implementation REVIEW_FILE parsing (review → prompt wiring)

Goal: Confirm `REVIEW_FILE` is accepted and parsed into a concise text summary (no codex required).

```bash
tmp="$(mktemp -d)"
cd "$tmp"
git init
git config user.email test@example.com
git config user.name test

echo "hello" > a.txt
git add a.txt
git commit -m "init"

mkdir -p .skilled-reviews/.implementation
cat > .skilled-reviews/.implementation/impl-guardrails.toml <<'TOML'
write_allow = [
  "hello.txt",
]

write_deny = [
  ".skilled-reviews/**",
  ".git/**",
]
TOML

mkdir -p .skilled-reviews/.estimation
cat > .skilled-reviews/.estimation/impl_smoke.md <<'MD'
# impl smoke

- Create `hello.txt` with `hello`.
MD

cat > review.json <<'JSON'
{
  "schema_version": 2,
  "facet": "Overall review (code-review)",
  "facet_slug": "overall",
  "status": "Blocked",
  "findings": [
    {
      "title": "[P0] example issue",
      "body": "example body",
      "confidence_score": 1.0,
      "priority": 0,
      "code_location": {
        "repo_relative_path": "a.txt",
        "line_range": {
          "start": 1,
          "end": 1
        }
      }
    }
  ],
  "questions": [],
  "uncertainty": [],
  "overall_correctness": "patch is incorrect",
  "overall_explanation": "example overall explanation",
  "overall_confidence_score": 1.0
}
JSON

python3 "$HOME/.codex/skills/implementation/scripts/extract_review_feedback.py" review.json

SOT='- none' ESTIMATION_FILE='.skilled-reviews/.estimation/impl_smoke.md' REVIEW_FILE='review.json' CODEX_BIN=true \
  "$HOME/.codex/skills/implementation/scripts/run_implementation.sh" \
  demo-scope --dry-run
echo "exit=$?"
```

Expected:
- `extract_review_feedback.py` prints `Status: Blocked` and includes `example issue`
- `run_implementation.sh --dry-run` returns `exit=0`
