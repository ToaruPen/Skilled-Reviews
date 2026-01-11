---
name: implement-cycle
description: "Standard branch-based implementation loop across any project: create a feature branch from the base branch, implement a single ticket/issue, always run required tests/checks, run review-cycle (or equivalent), and propose commit/push with explicit user confirmation. Use only when the user explicitly requests \"implement-cycle\" or \"impl\" or asks for the standard implement loop."
---

# Implement Cycle

## Overview

Run a repeatable, safe implementation loop for a single ticket/issue with clear checkpoints: rules, branch, implementation, tests/checks, review, and user-approved commit/push.

## Workflow

1. Identify repo rules and scope
   - Find and follow project rules (AGENTS/CONTRIBUTING/docs/ticket Scope).
   - Run `code-conventions` before implementation to locate and summarize repo-specific rules.
   - Base branch must be explicit (repo docs or user). If unclear, stop and ask. Feature prefix defaults to `feature/` unless the repo specifies otherwise.
   - If the task scope is unclear or conflicts with repo rules, stop and ask.

2. Check working tree safety
   - Run `git status` and confirm the tree is clean for the task.
   - Unexpected changes = scope-unrelated diffs, other-task work, generated artifacts, or third-party files. If present, stop and ask.

3. Create feature branch
   - Default to `git fetch` only. Do not merge/rebase without explicit approval.
   - Create a new feature branch from the base branch (e.g., `feature/<ticket-or-issue>`).
   - Branching rules (short):
     - Base → Feature (1 ticket/issue per branch) is the default.
     - New or unrelated work: create a new branch from base, not from the current feature branch.
     - Blocking fix outside scope: create a separate branch from base; merge it first, then update the original branch.
     - Feature → Feature' (stacked) only if the new work depends on unmerged changes; mark the dependency and keep it short-lived.

4. Implement within scope
   - Run the `estimation` skill before coding.
   - If `docs/.estimation` does not exist, create it before saving the estimate.
   - Save the estimate + implementation plan to `docs/.estimation/YYYY/MM/<ticket-or-issue>.md` (create folders as needed).
   - If the estimate exposes missing info or contradictions, stop and ask before coding.
   - Make the smallest change set that satisfies acceptance criteria.
   - Do not expand scope or introduce new architecture without explicit approval.
   - Update related docs/tickets (Evidence/WorkLog/DoD) when required by the project.
   - If no ticket/issue exists, treat the user request as the scope and confirm acceptance criteria before coding.

5. Always run tests and checks
   - Run the required tests/checks defined by the repo (docs/scripts/CI).
   - If the repo does not define them, ask the user for the minimum required commands.
   - If tests cannot run, stop and ask; record the reason before proceeding.
   - Record results in the ticket or designated log location if the project expects it.

6. Run review-cycle (or equivalent)
   - Determine the review path using `references/review-decision-table.md` (deterministic).
   - Low risk: run `code-review` only.
   - Medium risk: run Single Review via `review-cycle` if available; otherwise run `code-review` and note the deviation.
   - High risk or hard triggers: run `review-cycle` Parallel Review. If `review-cycle` is unavailable, run `code-review` and explicitly flag the missing parallel review as risk.
   - If `review-cycle` is used, skip re-scoring and follow the decision table result.
   - If both are run, treat `review-cycle` as the final decision; `code-review` is supplemental.
   - Provide required context to the reviewer:
     - Diff scope (staged or WIP)
     - SoT/Scope: project rules + ticket/spec/docs that define expected behavior
     - Estimation (required for impl flow): path to `docs/.estimation/...` entry created in step 4
     - Expectations: review-only, scope boundaries, tests run/not run
   - After an Approved or Approved with nits review, proceed to commit decisions in this flow (do not assume review-cycle will handle commits).

7. Stage and propose commit
   - Stage only the intended files.
   - Follow the `commit` skill message format (Conventional Commits + emoji); if the repo specifies a different format, ask the user before deviating.
   - Propose a commit message and always ask the user before committing.
   - Never amend or force-push unless explicitly requested.

8. Push and PR (optional)
   - Push only after explicit user approval.
   - If PR policy is unclear, ask before creating one.

9. Return to base branch for the next ticket
   - After merge or completion, switch back to the base branch and repeat for the next ticket.
   - Ask whether to delete the feature branch or keep it.

## Maintenance (for skill authors)

- Lightweight manual self-checks: `references/evaluations.md`
