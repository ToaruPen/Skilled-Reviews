---
name: pr-review
description: "Aggregates parallel review fragments (e.g., review-parallel outputs) into a single PR-level decision without re-reviewing the full diff. Use as review-cycle step 7-2 or when the user asks for an overall PR review focused on risk, conflicts, and approval readiness."
---

# PR Review

## Purpose
Aggregate 7-1 review fragments into a single PR-level decision. Do not re-review the diff.

## Inputs (required)
- Diff summary
- SoT (rules/specs/ticket scope)
- Tests (ran/not run)
- Review fragments (JSON)
- Constraints (optional)
- Estimation (optional, recommended in impl flow)

## Fixed facets (must exist)
- correctness
- edge-cases
- security
- performance
- tests-observability
- design-consistency

## Script (run from repo root)
Run:
`SOT="..." TESTS="..." bash "$HOME/.codex/skills/pr-review (impl)/scripts/run_pr_review.sh" <scope-id> [run-id] [--dry-run]`
Scope-id must match `[A-Za-z0-9._-]+`.
Scope-id must not be `.` or `..`.
Run-id must match `[A-Za-z0-9._-]+`.
Run-id must not be `.` or `..`.

Optional env: `CONSTRAINTS`, `DIFF_SUMMARY_FILE`, `DIFF_STAT`, `INTENT`, `RISKY`, `ESTIMATION`, `CODE_REVIEW_FILE`, `RUN_ID`, `SCHEMA_PATH`, `CODEX_BIN`, `MODEL`, `REASONING_EFFORT`, `VALIDATE`, `FORMAT_JSON`, `EXEC_TIMEOUT_SEC`
- `--dry-run` prints the planned actions and validates prerequisites without writing files; exits 0 if it would run, otherwise 1.
- `FORMAT_JSON=1` (default) pretty-formats the aggregate JSON output; set `FORMAT_JSON=0` to keep compact formatting.
- Execution timeout (harness): set command timeout to 1h; avoid EXEC_TIMEOUT_SEC unless a shorter, explicit limit is required.
Requirements: `git`, `python3`, `codex` CLI.

Behavior:
- Reads fragments from `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/<facet-slug>.json`
- If `code-review.json` exists, it is appended as an extra fragment (override with `CODE_REVIEW_FILE`).
- Requires diff summary (defaults to `diff-summary.txt` from 7-1)
- Writes aggregate to `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/aggregate/pr-review.json`
- Validates fragments by default; missing facets fail fast
- Ensures schema files exist by running `ensure_review_schemas.sh` (creates `docs/.reviews/schemas/*.json` if missing)

## Output schema
`docs/.reviews/schemas/pr-review.schema.json` (JSON only; use [] for empty arrays).

## Rules
- Do not request the full diff; use fragments + diff summary only.
- Prefer evidence-backed findings; ask if information is missing.
- Blocked only for high-confidence, high-impact issues or SoT violations.
