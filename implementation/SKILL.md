---
name: implementation
description: >-
  Generate a unified diff patch for implementing a scoped change via codex exec (read-only), then
  validate it against repo-local guardrails and apply it with git apply. Designed for implement-cycle Step 4.
---

# Implementation (Patch-Based)

## Purpose
Use `codex exec` to implement a scope by generating a unified diff patch (no direct writes), then apply it only after deterministic guardrail checks pass.

## When to use
- As `implement-cycle` Step 4 (estimation → scoped implementation).
- Standalone: when you want a patch-based implementation workflow with repo-local allow/deny paths.

## Guardrail model
- `codex exec` runs with `--sandbox read-only` (cannot write).
- The wrapper script validates the generated patch and applies it via `git apply` only if checks pass.

## Required inputs
- `SOT`: Source-of-truth for scope/rules (ticket/spec/AGENTS/docs paths or short summary).
- `ESTIMATION_FILE`: Path to the estimation document (usually under `.skilled-reviews/.estimation/...`).

## Optional inputs
- `PLAN_FILE`: Additional project-specific implementation plan file.
- `REVIEW_FILE`: Path to a review JSON (e.g., `.skilled-reviews/.reviews/.../code-review.json`) to drive a follow-up fix run.
- `CLARIFICATIONS`: Q&A appended after a Question stop.
- `CONSTRAINTS`: Extra constraints (e.g., "no refactors", "touch <= N files").

## Repo-local policy (required)
By default the script expects:
- `.skilled-reviews/.implementation/impl-guardrails.toml` (repo root)

It should be gitignored. Minimal recommended `.gitignore` entries:

```
/.skilled-reviews/.implementation/impl-guardrails.toml
/.skilled-reviews/.implementation/impl-runs/
```

Policy format (TOML subset: string arrays only):

```toml
write_allow = [
  "src/**",
]

write_deny = [
  "docs/**",
  ".skilled-reviews/**",
  ".gitignore",
]
```

Rules:
- Paths are repo-root relative (POSIX-style).
- `write_deny` overrides `write_allow`.
- Missing/invalid policy ⇒ fail-closed (no apply).

## Disallowed patch operations (v1, fail-closed)
- Renames/copies
- Deletes
- Mode changes
- Binary patches
- Symlinks/submodules
- New files are allowed only as `create mode 100644`

## Large patch safety
Auto-apply is blocked when:
- `lines_changed > 600` OR `files_changed > 15` OR `subsystems >= 3` OR any binary change

Override with `ALLOW_LARGE_PATCH=1`.

## Script (run from repo root)

Generate + validate + apply:
`SOT="..." ESTIMATION_FILE=".skilled-reviews/.estimation/..." "$HOME/.codex/skills/implementation (impl)/scripts/run_implementation.sh" <scope-id> [run-id]`

Dry-run (checks prerequisites only):
`SOT="..." ESTIMATION_FILE="..." "$HOME/.codex/skills/implementation (impl)/scripts/run_implementation.sh" <scope-id> [run-id] --dry-run`

Follow-up fix run (after a Blocked/Question review):
`SOT="..." ESTIMATION_FILE="..." REVIEW_FILE=".skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<review-run-id>/code-review.json" CONSTRAINTS="touch only ..." "$HOME/.codex/skills/implementation (impl)/scripts/run_implementation.sh" <scope-id> <new-run-id>`

## Outputs
- Patch (model output): `.skilled-reviews/.implementation/impl-runs/<scope-id>/<run-id>/patch.diff`
- Logs/metadata: `.skilled-reviews/.implementation/impl-runs/<scope-id>/<run-id>/...` (best-effort)
