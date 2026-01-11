# Skilled-Reviews

A repository bundling Codex CLI `impl` (alias of `implement-cycle`) plus review-related skills (`review-cycle`, `review-parallel`, `code-review`, `pr-review`) and their helper scripts.

## Included skills

- `impl` (alias)
- `implement-cycle`
- `review-cycle (impl)`
- `review-parallel (impl)`
- `code-review (impl)`
- `pr-review (impl)`

## Prerequisites

- `git`
- `bash`
- `python3`
- `codex` CLI (required only when you actually generate review JSON)

## Install

Copies these skills into `~/.codex/skills/` (or under `CODEX_HOME`).

```bash
./scripts/install.sh
```

## Usage (example)

```bash
export SOT='- <rules/specs/ticket>'
export TESTS='- <ran / not run>'

"$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" demo-scope --dry-run
```

Key toggles:
- `--dry-run`: preflight only (no writes). `exit 0` when ready; `exit 1` when inputs/env are insufficient.
- `VALIDATE=1` (default): validate JSON outputs (detect breakage).
- `FORMAT_JSON=1` (default): pretty-format JSON outputs (indent=2).
- `REASONING_EFFORT` (default: `xhigh`): override to your preferred reasoning effort (e.g., `REASONING_EFFORT=high`).

## Output location

All scripts write under the target repository root:
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/...`

`scope-id` / `run-id` must match `^[A-Za-z0-9._-]+$` and must not be `.` or `..` (no `/`).

## Self test

```bash
./scripts/self_test.sh
```

The test stubs out the `codex` binary, so it can run without a local `codex` install (but still requires `bash`/`git`/`python3`).

## CI

GitHub Actions runs `scripts/self_test.sh`: `.github/workflows/ci.yml`
