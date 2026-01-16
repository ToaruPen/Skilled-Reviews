---
name: impl-np
description: >-
  Quota-saving implement loop: estimation → patch-based implementation (via `implementation`) → tests/checks → code-review only (no review-parallel/pr-review).
---

# impl-np

Quota-saving implement loop that **must**:
- implement via `codex exec` patch generation (`implementation` skill), and
- delegate review to a separate `codex exec` run (`code-review` skill),
with no parallel review.

This skill is based on `implement-cycle (no-parallel)`, but makes the handoffs explicit so the
estimation → implementation → review chain is deterministic.

## Workflow (strict)

1. Identify rules + scope
   - Read repo rules (e.g., `AGENTS.md`, tickets/specs) and define the SoT for this scope.

2. Ensure working tree safety (required)
   - `git status --porcelain` must be clean for the scope.

3. Create feature branch
   - Base branch must be explicit (docs/user).

4. Estimation (required)
   - Run the `estimation` skill and save to:
     `.skilled-reviews/.estimation/YYYY/MM/<scope-id>.md`
   - You will pass this file path as `ESTIMATION_FILE` to the implementation step.

## Step 4 (override): Implementation must be patch-based

- Always implement via the `implementation` skill (patch generation via `codex exec` + deterministic guardrail checks + apply).
- Do not make manual edits during Step 4 unless the user explicitly requests/approves a manual deviation.
- Ensure the target repo has a repo-local policy at `.skilled-reviews/.implementation/impl-guardrails.toml` (required; missing/invalid should fail-closed).
- Note: the wrapper script fails if there are **any** staged or unstaged changes (`git diff` / `git diff --cached` must be empty).

Command template (run from repo root):
`SOT="..." ESTIMATION_FILE=".skilled-reviews/.estimation/..." "$HOME/.codex/skills/implementation (impl)/scripts/run_implementation.sh" <scope-id> [run-id]`

5. Tests / checks (required)
   - Run repo-standard checks. If none exist, ask the user for the minimum set.

6. Review (required; no-parallel)
   - Ensure the diff is reviewable (include new files):
     - Prefer `git add -A` to stage intended changes, OR
     - `git add -N <paths>` for new files if you want to keep changes unstaged.
   - Run `code-review` (read-only) via script:
     `SOT=$'- <ticket/spec/rules>\n- Estimation: .skilled-reviews/.estimation/...' TESTS="..." "$HOME/.codex/skills/code-review (impl, single-review)/scripts/run_code_review.sh" <scope-id> [run-id]`
   - If the review is Blocked/Question:
     - Re-run `implementation` using `REVIEW_FILE=.skilled-reviews/.reviews/.../code-review.json` and a new run-id.
     - Then re-run Step 5 and Step 6 until Approved / Approved with nits.

7. Commit / push
   - Propose commit message; commit/push only with explicit user approval.
