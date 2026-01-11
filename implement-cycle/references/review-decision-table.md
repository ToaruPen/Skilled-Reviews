# Review Routing Decision Table

Purpose: Deterministically select the review path in implement-cycle Step 6.

## Inputs
- lines_changed: additions + deletions from `git diff --numstat` (sum numeric entries only).
- files_changed: number of files changed from `git diff --name-only`.
- subsystems: distinct top-level directories/modules touched (root files count as "root").
- hard_triggers: authn/authz, secrets, payments, migrations, destructive changes.
- ops_impact: infra/deploy/runtime config changes that can affect production behavior.
- binary_change: true if any `git diff --numstat` entry uses "-" for added/deleted (binary/opaque).

## Decision Table

| Condition (evaluate top to bottom) | Risk | Review Path |
| --- | --- | --- |
| Any hard_triggers == true | High | Parallel Review (`review-parallel` → `pr-review`) |
| lines_changed > 600 OR files_changed > 15 OR subsystems >= 3 OR ops_impact == true | High | Parallel Review (`review-parallel` → `pr-review`) |
| lines_changed 201-600 OR files_changed 6-15 OR subsystems == 2 | Medium | Single Review (review-cycle single) |
| lines_changed <= 200 AND files_changed <= 5 AND subsystems == 1 AND ops_impact == false | Low | code-review only |

## Adjustments
- If no tests run for non-trivial changes, bump risk by one level.
- If diff contains only docs/comments or formatting, allow a one-level downgrade.
- If binary_change == true and risk would be Low, bump to Medium.

## Measurement Notes
- Example commands:
  - `git diff --numstat` to compute lines_changed and detect binary changes ("-").
  - `git diff --name-only` to compute files_changed and subsystems.
- Record computed values in the review log or ticket as evidence.
