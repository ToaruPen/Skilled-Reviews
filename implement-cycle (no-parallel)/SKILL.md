---
name: implement-cycle (no-parallel)
description: >-
  Quota-saving variant of implement-cycle: estimation → implement → tests/checks → code-review only (no review-parallel/pr-review). Use only when the user explicitly requests "implement-cycle (no-parallel)".
---

# implement-cycle (no-parallel)

This skill is a thin wrapper around `implement-cycle`.
Follow the `implement-cycle` workflow exactly, except replace Step 6 with the no-parallel flow below.

## Step 6 (override): No parallel review

- Always run `code-review` (read-only).
  - Prefer the script form (run from repo root):
    `SOT="..." TESTS="..." "$HOME/.codex/skills/code-review (impl, single-review)/scripts/run_code_review.sh" <scope-id> [run-id]`
- Never run `review-parallel` or `pr-review` in this skill.
- If you detect hard triggers (authn/authz, secrets, payments, migrations, destructive changes) or ops-impact changes, stop and ask whether to:
  - proceed anyway with `code-review` only, or
  - switch back to full `implement-cycle` (decision table + review-cycle).
- Provide the reviewer inputs:
  - Diff scope (staged/WIP/commit range)
  - SoT (rules/spec/ticket)
  - Tests (ran/not run)
  - Estimation path (from Step 4 in implement-cycle)
  - Expectations: review-only; read-only; do not edit
- If review is Blocked/Question:
  - Prefer re-running patch-based implementation (if using the `implementation` skill) with a new run-id and the review findings as input (`REVIEW_FILE` or `CLARIFICATIONS`) instead of manual edits.
  - Then rerun Step 5 (tests/checks) and rerun `code-review` until Approved / Approved with nits.
