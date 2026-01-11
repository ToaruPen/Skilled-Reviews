---
name: review-cycle
description: >-
  Implementation-side review loop using codex exec to request an independent review via the code-review skill, iterate on Blocked/Question findings, and confirm readiness for the next step. Use when an implementation agent should run a repeatable review -> fix -> approve cycle. Keywords: review cycle, review loop, codex exec, approval gate, implementation, refactor, refactoring, 実装, リファクタ, リファクタリング.
---

# Review Cycle

## Purpose
Run a repeatable implementation-side review loop using codex exec until Approved or Approved with nits.

## When to use
- After completing a scope (ticket/PR/issue) and before commit/push.
- Use Single Review for low-risk changes; use Parallel Review for higher risk or complex changes.
- Script-only: review-cycle runs via helper scripts; manual codex exec is out of scope.
- If code-review is also run, treat review-cycle as the final decision; code-review is supplemental.

## Mode selection (score)
- If an upstream workflow already selected a mode (e.g., implement-cycle decision table), use that decision and skip re-scoring.
- Otherwise score 0-3 each and sum across: change size, impact scope, risk, complexity, tests, ops impact, dependencies.
  - 0: docs/comments/formatting only; no behavior change
  - 1: small, localized change (<=200 lines, <=5 files, 1 subsystem)
  - 2: medium change (201-600 lines or 6-15 files or 2 subsystems or tests not run)
  - 3: large change (>600 lines or >15 files or >=3 subsystems or ops impact)
  - Use these thresholds as guidance and keep them aligned with the implement-cycle decision table.
Hard triggers: authn/authz, secrets, payments, migrations, destructive changes.
Decision: total <= 9 => Single Review; total >= 10 or hard trigger => Parallel Review (7-1 + 7-2).

## Inputs (required)
- Diff (WIP/staged/commit range)
- SoT (rules/specs/ticket scope)
- Tests (ran/not run summary)
- Estimation (required in impl flow if it exists)

## Workflow
1. Finish implementation for the current scope.
2. If no upstream decision exists, choose Single or Parallel Review using the score above.
3. Single Review: run the code-review script once (read-only) to produce `code-review.json`.
4. Parallel Review:
   - 7-1: run review-parallel and store facet JSONs under `docs/.reviews/`.
     - By default it validates outputs and pretty-formats JSON (`VALIDATE=1`, `FORMAT_JSON=1`).
   - If validation fails: fix inputs, then re-run only missing/invalid facets.
   - 7-2: run pr-review to aggregate fragments (no full diff; use diff summary only).
     - If `code-review.json` exists under the same run-id, it will be appended as a supplemental fragment.
5. If Blocked/Question: fix or add context, then re-run the affected step(s).
6. Stop when status is Approved or Approved with nits.

## Scripts (run from repo root)
- Run Single Review (code-review):
  `SOT="..." TESTS="..." "$HOME/.codex/skills/code-review (impl)/scripts/run_code_review.sh" <scope-id> [run-id]`
- Run review-parallel (7-1):
  `SOT="..." TESTS="..." "$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" <scope-id> [run-id]`
- Validate fragments:
  `python3 "$HOME/.codex/skills/review-parallel (impl)/scripts/validate_review_fragments.py" <scope-id> [run-id] [--format]`
- Run pr-review (7-2):
  `SOT="..." TESTS="..." bash "$HOME/.codex/skills/pr-review (impl)/scripts/run_pr_review.sh" <scope-id> [run-id]`
Scope-id must match `[A-Za-z0-9._-]+`.
Scope-id must not be `.` or `..`.
Run-id must match `[A-Za-z0-9._-]+`.
Run-id must not be `.` or `..`.
- `run_code_review.sh`, `run_review_parallel.sh`, and `run_pr_review.sh` accept `--dry-run` (no-write preview; exits 0 if it would run, otherwise 1).
- Shared optional env (recommended defaults):
  - `VALIDATE=1` validates JSON outputs (set `VALIDATE=0` to skip).
  - `FORMAT_JSON=1` pretty-formats JSON outputs (set `FORMAT_JSON=0` to keep compact formatting).

## Execution timeout
- When running review scripts via the execution harness, set a long command timeout (1h) to avoid premature termination.
- Do not set EXEC_TIMEOUT_SEC unless a shorter, explicit limit is required.

## Outputs
- Single Review: `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/code-review.json`
- 7-1: `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/<facet-slug>.json`
- 7-1 diff summary: `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/diff-summary.txt`
- 7-2: `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/aggregate/pr-review.json`

## Guardrails
- Read-only review; no code edits.
- 7-2 must not re-review the full diff; use fragments + diff summary.
- Keep 7-1 and 7-2 inputs consistent (diff/SoT/tests); change inputs => new run-id.
- Include untracked files when needed: `git add -N .` before diff generation.
