# Skilled-Reviews Wiki (EN)

See also: `docs/wiki_ja.md` (Japanese)

## Purpose

This document is a human-friendly reference for how to run the included review scripts (what inputs they need, what they write, and which knobs exist).

Source of truth: the script output (`Usage:` / `Optional env:`) is authoritative. This wiki may lag behind.

## Concepts

- **scope-id**
  - A stable identifier for “what is being reviewed” (ticket/PR/etc.). Used as a directory name.
  - Rules: `^[A-Za-z0-9._-]+$` and must not be `.` or `..` (no `/`).
- **run-id**
  - An identifier for one review run under a given `scope-id`.
  - Rules: `^[A-Za-z0-9._-]+$` and must not be `.` or `..` (no `/`).
- **SoT (`SOT`)**
  - “Source of Truth” for the expected behavior: ticket/spec/rules/docs. Required by review scripts.
- **Tests (`TESTS`)**
  - What you ran (or didn’t) and why. Required by review scripts.
- **7-1 / 7-2**
  - `review-parallel` creates facet fragments (7-1).
  - `pr-review` aggregates fragments into a single decision (7-2).

## Output layout

All review artifacts are written under the *target repository root* (the repo you are reviewing):

- `docs/.reviews/schemas/`
  - `review-fragment.schema.json`
  - `pr-review.schema.json`
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/`
  - `diff-summary.txt` (from 7-1, unless overridden)
  - `<facet-slug>.json` (7-1 fragments)
  - `code-review.json` (optional overall fragment)
  - `aggregate/pr-review.json` (7-2 output)
  - `../.current_run` (tracks the most recent `run-id` for that `scope-id`)

## Installation

Install into your Codex skills directory:

```bash
./scripts/install.sh
```

Options (see `./scripts/install.sh --help` for the latest):
- `--dest <skills-dir>`: destination directory (default: `${CODEX_HOME:-$HOME/.codex}/skills`)
- `--link`: install via symlinks instead of copying
- `--dry-run`: print the plan and perform no writes

## Quick start

In the repository you want to review (must be a git repo):

```bash
export SOT='- <ticket/spec/rules>'
export TESTS='- <ran / not run>'

# 7-1: parallel facets (writes fragments + diff summary)
"$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" demo-scope

# 7-2: aggregate (uses diff summary + fragments only)
bash "$HOME/.codex/skills/pr-review (impl)/scripts/run_pr_review.sh" demo-scope
```

## Defaults and customization

Each script has its own defaults (model/effort). Override via environment variables.

Defaults (as of this repo state; confirm via `--dry-run`):
- `review-parallel`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=high`
- `code-review`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=xhigh`
- `pr-review`: `MODEL=gpt-5.2`, `REASONING_EFFORT=xhigh`

Example:

```bash
MODEL=gpt-5.2-codex REASONING_EFFORT=high \
  "$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" demo-scope
```

Notes:
- `review-parallel` runs multiple facets; higher effort increases latency and usage across all facets.
- A practical pattern is: start with `high`, then rerun only the weak/uncertain facet(s) with `xhigh`.

## Script reference

### `review-parallel`: `run_review_parallel.sh` (7-1)

Generates per-facet review fragments (JSON) and a diff summary; updates `.current_run` only after success.

Run:

```bash
SOT="..." TESTS="..." \
  "$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" <scope-id> [run-id] [--dry-run]
```

Args:
- `<scope-id>`: required
- `[run-id]`: optional (`RUN_ID` / `.current_run`, otherwise an auto timestamp)
- `--dry-run`: preflight only; no writes. Exits `0` if ready; `1` if insufficient.
  - `--dry-run` can be placed anywhere in argv.
  - Only `--dry-run` is supported; unknown `--foo` will error.

Diff selection:
- `DIFF_MODE=auto` prefers the staged diff when non-empty; unstaged changes are ignored in that case.
- Use `DIFF_MODE=worktree` to include unstaged changes.
- If you need to include untracked files, consider `git add -N .` before diffing.

Supported env (summary):
- Required: `SOT`, `TESTS`
- Optional (see the script’s `Optional env:` for the full list):
  - `MODEL`, `REASONING_EFFORT`
  - `DIFF_MODE`, `DIFF_FILE`, `STRICT_STAGED`
  - `VALIDATE` (default `1`), `FORMAT_JSON` (default `1`)
  - `EXEC_TIMEOUT_SEC`, `CODEX_BIN`, `SCHEMA_PATH`, ...

Outputs:
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/<facet>.json`
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/diff-summary.txt` (default)

### `review-parallel`: `validate_review_fragments.py`

Validates fragment JSONs in a run, and can rewrite them with pretty formatting.

Run:

```bash
python3 "$HOME/.codex/skills/review-parallel (impl)/scripts/validate_review_fragments.py" \
  <scope-id> [run-id] --format
```

Key options:
- `--facets <csv>`: validate only selected facets
- `--schema <path>`: schema path
- `--extra-file <path> --extra-slug <slug>`: validate an extra fragment (e.g. `code-review.json`)
- `--format`: rewrite validated JSON with indent=2

### `code-review`: `run_code_review.sh` (Single / overall fragment)

Produces one overall review fragment as JSON (`code-review.json`).

Run:

```bash
SOT="..." TESTS="..." \
  "$HOME/.codex/skills/code-review (impl)/scripts/run_code_review.sh" <scope-id> [run-id] [--dry-run]
```

Notes:
- `--dry-run` can be placed anywhere in argv; unknown `--foo` will error.
- Uses `DIFF_MODE=auto` (staged preferred) by default; see `review-parallel` notes.
- Validates and (optionally) pretty-formats output when `VALIDATE=1`.

Output:
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/code-review.json`

### `pr-review`: `run_pr_review.sh` (7-2)

Aggregates 7-1 fragments into a single PR-level JSON decision. Does not re-review the full diff.

Run:

```bash
SOT="..." TESTS="..." \
  bash "$HOME/.codex/skills/pr-review (impl)/scripts/run_pr_review.sh" <scope-id> [run-id] [--dry-run]
```

Requirements:
- The run directory must already exist and contain all fixed facets + a diff summary.
- If `run-id` is omitted, `.current_run` must exist (no auto-generation).
- `python3` is always required for `pr-review` (it reads fragments and normalizes output).

Diff summary:
- Provide via `DIFF_SUMMARY_FILE` or `DIFF_STAT`, otherwise it uses `diff-summary.txt` under the run directory.

Output:
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/aggregate/pr-review.json`

### `review-parallel`: `ensure_review_schemas.sh`

Creates schema files in the target repo if missing (does not overwrite).

Files:
- `docs/.reviews/schemas/review-fragment.schema.json`
- `docs/.reviews/schemas/pr-review.schema.json`

## Troubleshooting

- **Diff is empty / Diff is empty (staged and worktree)**
  - You may be running with no staged/unstaged changes. Stage changes or set `DIFF_MODE=worktree`.
- **`DIFF_MODE=auto` ignores unstaged changes**
  - This is by design (staged preferred). Use `DIFF_MODE=worktree`.
- **`STRICT_STAGED=1 and staged diff is empty`**
  - You forced staged-only review but nothing is staged. Either stage changes or set `STRICT_STAGED=0`.
- **Invalid scope-id / run-id**
  - Only `A-Za-z0-9._-` are allowed (and not `.`/`..`).
- **`python3 not found`**
  - Install Python 3, or set `VALIDATE=0` where supported. (`pr-review` always needs Python.)

