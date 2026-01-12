---
name: code-review
description: >-
  Language-agnostic code review workflow for PRs/commits/diffs. Use when the user asks for a code review, PR review, diff review, pre-commit final check, or quality/security verification. If the project provides SoT/rules/CI/static checks, prioritize those; if information is missing, stop and ask instead of guessing.
---

# Code Review

## Overview

Quickly surface risk in this order: safety → requirement alignment → correctness → tests → security → maintainability.
Designed for lightweight reviews (manual execution is OK; allows reviewer judgment). For deterministic workflows, use `review-cycle`.
If you run both, treat `review-cycle` as the final decision and `code-review` as supplemental.
Can be used standalone.

## Workflow

1. Confirm required inputs (diff/SoT/expectations/tests). If missing, stop and ask.
2. Understand the change set and impact areas (API/DB/auth/billing/crypto/infra, etc.).
3. Apply guardrails (Blocked/Question).
   - If you must force a strict output format, do not depend on subcommands; pipe the diff and prompt directly into `codex exec`.
4. Run the repo’s standard verification commands when possible.
5. Organize findings using the review focus facets.
6. Provide a conclusion and next actions using the output template.

## Priority Order

1) Project SoT / rules / CI (`AGENTS.md`, `CONTRIBUTING.md`, `README`, `docs/`, tickets/issues/PR body, CI config)
2) User request (review-only vs can-fix vs can-commit/push)
3) This skill’s review focus facets

## Inputs to Provide

- The diff scope to review (PR/branch/commit range/`uncommitted`)
- Requirement SoT (ticket/issue/spec/PR body; at least one)
- Review expectations:
  - review-only (comments only)
  - review + fix (you may fix)
  - review + commit (you may commit)
  - review + commit + push (you may push)
- Verification trail (standard commands + results: build/test/lint/typecheck/security, etc.)

If anything is missing, stop with **Question**.

## Diff Selection Priority

1) `git diff --staged` (final pre-commit review)
2) `git diff` (unstaged WIP review)
3) `git show <commit>` / `git diff <base>...HEAD` (PR/commit review)

Reviewing unstaged changes is allowed.

## Request Template

```
Please review the current changes.
Provide Status: Blocked | Approved | Approved with nits | Question, with Blockers/Questions/Plan/Notes/Evidence.

Diff: <paste or specify how to obtain>
SoT: <ticket/docs>
Expectations: review-only; read-only; do not edit
Tests: <what ran / not run>
```

## Guardrails

- Diff does not align with SoT / unrelated changes mixed in → Blocked
- Suspected violations (forbidden areas/ownership boundaries/data handling/licenses, etc.) → Blocked (use Question if not sure)
- Spec is ambiguous/undefined/contradictory → Question (briefly state disputes/options/impact/recommendation)

## Review Focus (facet-aligned)

- Correctness and logic: normal-path behavior, invariants
- Edge cases and error handling: boundary/empty/failure handling
- Security and data safety: validation, auth, secrets, exposure
- Performance and resource use: hot paths, I/O, memory
- Tests and observability: coverage, regression, logging/metrics
- Design/consistency with project rules: layering, naming, responsibilities, maintainability

## Output Template

- Status: Blocked / Approved / Approved with nits / Question
- Blockers: issue + concrete fix idea (required when Blocked)
- Questions: what extra information is needed (required when Question)
- Plan: when Blocked/Question, propose a shortest 3–6 step plan
- Notes: optional improvement suggestions
- Evidence: what you checked (commands/logs/SoT); what you did not check
- Next: next actions

## Optional JSON Output (review-cycle integration)

- Path: `.skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<run-id>/code-review.json`
- Schema: `.skilled-reviews/.reviews/schemas/review-fragment.schema.json`
- Use `facet="Overall review (code-review)"` and `facet_slug="overall"`
- Generate via `codex exec --output-schema <schema> --output-last-message <path>` (JSON only)

## Scripts (optional)

- Single Review (review-cycle integration):
  `SOT="..." TESTS="..." "$HOME/.codex/skills/code-review/scripts/run_code_review.sh" <scope-id> [run-id] [--dry-run]`
- Scope-id must match `[A-Za-z0-9._-]+`.
- Scope-id must not be `.` or `..`.
- Run-id must match `[A-Za-z0-9._-]+`.
- Run-id must not be `.` or `..`.
- Optional env: RUN_ID, CONSTRAINTS, DIFF_FILE, DIFF_MODE, STRICT_STAGED, SCHEMA_PATH, CODEX_BIN, MODEL, REASONING_EFFORT, EXEC_TIMEOUT_SEC, VALIDATE, FORMAT_JSON
- `DIFF_MODE=auto` uses the staged diff when non-empty; unstaged changes are ignored in that case. Use `DIFF_MODE=worktree` to include unstaged changes.
- `VALIDATE=1` (default) validates the output JSON; set `VALIDATE=0` to skip validation.
- `FORMAT_JSON=1` (default) pretty-formats the output JSON during validation; set `FORMAT_JSON=0` to keep raw formatting.
- `--dry-run` prints the planned actions and validates prerequisites without writing files; exits 0 if it would run, otherwise 1.
- Requirements: `git`, `codex` CLI, `python3` (unless `VALIDATE=0`).
- Output: `.skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<run-id>/code-review.json`
- Execution timeout (harness): set command timeout to 1h; avoid EXEC_TIMEOUT_SEC unless a shorter, explicit limit is required.

## Status Rules

- Blocked: requires fixes
- Question: cannot decide due to missing info
- Approved: no blockers
- Approved with nits: only minor improvements (no spec/safety impact)

## Commit/Push Policy

Treat commit/push as separate work; only do it when the user explicitly asks.

## Language

Follow the repository’s language conventions; otherwise match the user’s language.
