---
name: review-parallel
description: "Creates parallel code review fragments across focused facets (correctness, security, performance, tests, design) without making code changes. Use for higher-risk or complex changes, especially as the facet-fragment step in review-cycle Parallel Review or when the user asks for parallelized codex exec reviews."
---

# Review Parallel

## Purpose
Create focused review fragments per facet for a single diff. Output JSON only; do not edit code.

## Inputs (required)
- Diff scope
- SoT (rules/specs/ticket scope)
- Tests (ran/not run)
- Constraints (optional)

## Default facets (fixed)
- correctness
- edge-cases
- security
- performance
- tests-observability
- design-consistency

## Script (run from repo root)
Run:
`SOT="..." TESTS="..." "$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" <scope-id> [run-id] [--dry-run]`
Scope-id must match `[A-Za-z0-9._-]+`.
Scope-id must not be `.` or `..`.
Run-id must match `[A-Za-z0-9._-]+`.
Run-id must not be `.` or `..`.

Optional env: `CONSTRAINTS`, `DIFF_FILE`, `DIFF_MODE`, `STRICT_STAGED`, `DIFF_SUMMARY_OUT`, `RUN_ID`, `SCHEMA_PATH`, `CODEX_BIN`, `MODEL`, `REASONING_EFFORT`, `EXEC_TIMEOUT_SEC`, `VALIDATE`, `FORMAT_JSON`
- `DIFF_MODE=auto` uses the staged diff when non-empty; unstaged changes are ignored in that case. Use `DIFF_MODE=worktree` to include unstaged changes.
- `VALIDATE=1` (default) validates outputs; set `VALIDATE=0` to skip validation.
- `FORMAT_JSON=1` (default) pretty-formats JSON outputs during validation; set `FORMAT_JSON=0` to keep raw formatting.
- `REASONING_EFFORT=high` (default) can be overridden (e.g., `REASONING_EFFORT=xhigh`) depending on your latency/cost/quality preference.
- `--dry-run` prints the planned actions and validates prerequisites without writing files; exits 0 if it would run, otherwise 1.
- Execution timeout (harness): set command timeout to 1h; avoid EXEC_TIMEOUT_SEC unless a shorter, explicit limit is required.
Requirements: `git`, `codex` CLI, `python3` (unless `VALIDATE=0`).

Behavior:
- Writes fragments to `.skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<run-id>/<facet-slug>.json`
- Writes diff summary to `.skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<run-id>/diff-summary.txt`
- Updates `.current_run` only after all facets succeed
- Ensures schema files exist by running `ensure_review_schemas.sh` (creates `.skilled-reviews/.reviews/schemas/*.json` if missing)

## Output schema
`.skilled-reviews/.reviews/schemas/review-v2.schema.json` (JSON only; use [] for empty arrays).

## Validation
Run:
`python3 "$HOME/.codex/skills/review-parallel (impl)/scripts/validate_review_fragments.py" <scope-id> [run-id] [--format]`
- `--format` rewrites validated JSON files with pretty formatting.

## Rules
- Review only the assigned facet; keep inputs consistent across facets.
- Evidence is required; mark uncertainty explicitly.
- Blocked only for high-confidence, high-impact issues.
