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
- **Estimation (`ESTIMATION_FILE`)**
  - Path to an estimation/plan document used by `implementation` (patch-based implementation).
- **Review scripts / skills**
  - `code-review` (single): reviews the target diff once and writes `code-review.json` (read-only; no code edits).
  - `review-cycle`: implementation-side review loop; chooses single (`code-review`) or parallel (`review-parallel` → `pr-review`) based on risk, then reruns as needed until Approved.
  - `review-parallel` (parallel facets): writes per-facet fragments (`<facet-slug>.json`) plus `diff-summary.txt` (read-only; no code edits).
  - `pr-review` (aggregate): aggregates `diff-summary.txt` + fragments (and optional `code-review.json`) into `aggregate/pr-review.json` (does not re-review the full diff).
- **Implementation script / skill**
  - `implementation` (patch-based): generates a unified diff patch via `codex exec --sandbox read-only`, validates it against repo-local guardrails, then applies it with `git apply`.

## Output layout

All review artifacts are written under the *target repository root* (the repo you are reviewing):

- `.skilled-reviews/.reviews/schemas/`
  - `review-v2.schema.json`
- `.skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<run-id>/`
  - `diff-summary.txt` (from `review-parallel` by default, unless overridden)
  - `<facet-slug>.json` (`review-parallel` fragments)
  - `code-review.json` (optional overall fragment)
  - `aggregate/pr-review.json` (`pr-review` output)
  - `../.current_run` (tracks the most recent `run-id` for that `scope-id`)

Implementation artifacts are written under the *target repository root* as well:

- `.skilled-reviews/.implementation/impl-runs/<scope-id>/<run-id>/`
  - `raw.txt` (raw model output)
  - `patch.diff` (extracted unified diff patch)

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

# `review-parallel`: parallel facets (writes fragments + diff summary)
"$HOME/.codex/skills/review-parallel/scripts/run_review_parallel.sh" demo-scope

# `pr-review`: aggregate (uses diff summary + fragments only)
bash "$HOME/.codex/skills/pr-review/scripts/run_pr_review.sh" demo-scope
```

Patch-based implementation (requires repo-local guardrails in the target repo):

```bash
export SOT='- <ticket/spec/rules>'
export ESTIMATION_FILE='.skilled-reviews/.estimation/YYYY/MM/<scope>.md'

"$HOME/.codex/skills/implementation/scripts/run_implementation.sh" demo-scope --dry-run
```

## Defaults and customization

Each script has its own defaults (model/effort). Override via environment variables.

Defaults (as of this repo state; confirm via `--dry-run`):
- `implementation`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=high`
- `review-parallel`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=high`
- `code-review`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=xhigh`
- `pr-review`: `MODEL=gpt-5.2`, `REASONING_EFFORT=xhigh`

Example:

```bash
MODEL=gpt-5.2-codex REASONING_EFFORT=high \
  "$HOME/.codex/skills/review-parallel/scripts/run_review_parallel.sh" demo-scope
```

Notes:
- `review-parallel` runs multiple facets; higher effort increases latency and usage across all facets.
- A practical pattern is: start with `high`, then rerun only the weak/uncertain facet(s) with `xhigh`.

## Script reference

### `review-parallel`: `run_review_parallel.sh`

Generates per-facet review fragments (JSON) and a diff summary; updates `.current_run` only after success.

Run:

```bash
SOT="..." TESTS="..." \
  "$HOME/.codex/skills/review-parallel/scripts/run_review_parallel.sh" <scope-id> [run-id] [--dry-run]
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
- `.skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<run-id>/<facet>.json`
- `.skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<run-id>/diff-summary.txt` (default)

### `review-parallel`: `validate_review_fragments.py`

Validates fragment JSONs in a run, and can rewrite them with pretty formatting.

Run:

```bash
python3 "$HOME/.codex/skills/review-parallel/scripts/validate_review_fragments.py" \
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
  "$HOME/.codex/skills/code-review/scripts/run_code_review.sh" <scope-id> [run-id] [--dry-run]
```

Notes:
- `--dry-run` can be placed anywhere in argv; unknown `--foo` will error.
- Uses `DIFF_MODE=auto` (staged preferred) by default; see `review-parallel` notes.
- Validates and (optionally) pretty-formats output when `VALIDATE=1`.

Output:
- `.skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<run-id>/code-review.json`

### `pr-review`: `run_pr_review.sh`

Aggregates `review-parallel` fragments into a single PR-level JSON decision. Does not re-review the full diff.

Run:

```bash
SOT="..." TESTS="..." \
  bash "$HOME/.codex/skills/pr-review/scripts/run_pr_review.sh" <scope-id> [run-id] [--dry-run]
```

Requirements:
- The run directory must already exist and contain all fixed facets + a diff summary.
- If `run-id` is omitted, `.current_run` must exist (no auto-generation).
- `python3` is always required for `pr-review` (it reads fragments and normalizes output).

Diff summary:
- Provide via `DIFF_SUMMARY_FILE` or `DIFF_STAT`, otherwise it uses `diff-summary.txt` under the run directory.

Output:
- `.skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<run-id>/aggregate/pr-review.json`

### `implementation`: `run_implementation.sh` (Patch-based implementation)

Generates a unified diff patch (via `codex exec --sandbox read-only`), validates it against repo-local guardrails, then applies it with `git apply` when allowed.

Run (from the target repo root):

```bash
SOT="..." ESTIMATION_FILE=".skilled-reviews/.estimation/..." \
  "$HOME/.codex/skills/implementation/scripts/run_implementation.sh" <scope-id> [run-id] [--dry-run]
```

Notes:
- Requires a repo-local policy at `.skilled-reviews/.implementation/impl-guardrails.toml` (recommended to gitignore).
- Aborts if there are staged/unstaged changes (to avoid mixing scopes).
- Set `APPLY=0` to generate + validate only (no apply).
- After a Blocked/Question review, pass `REVIEW_FILE=.skilled-reviews/.reviews/.../code-review.json` (or `pr-review.json`) to drive a follow-up fix run.

### `implementation`: `validate_implementation_patch.py`

Validates a patch against the guardrails policy (and `git apply --check`).

Run (from the target repo root):

```bash
python3 "$HOME/.codex/skills/implementation/scripts/validate_implementation_patch.py" \
  --repo-root . --patch <patch.diff> --policy .skilled-reviews/.implementation/impl-guardrails.toml
```

### `review-parallel`: `ensure_review_schemas.sh`

Creates schema files in the target repo if missing (does not overwrite).

Files:
- `.skilled-reviews/.reviews/schemas/review-v2.schema.json`

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
