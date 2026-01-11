# Skilled-Reviews Wiki

## Purpose / 目的

**EN:** This document is a human-friendly reference for how to run the included review scripts (what inputs they need, what they write, and which knobs exist).  
**JA:** 同梱スクリプトを運用するための、人間向けリファレンスです（必要入力・出力先・調整できる設定など）。

**EN (Source of truth):** the script output (`Usage:` / `Optional env:`) is authoritative. This wiki may lag behind.  
**JA（正）:** スクリプトが出力する `Usage:` / `Optional env:` が正です（wikiは追随が遅れる可能性があります）。

## Concepts / 用語

- **scope-id**  
  **EN:** A stable identifier for “what is being reviewed” (ticket/PR/etc.). Used as a directory name.  
  **JA:** 「何をレビューしているか」を表す識別子（チケット/PR等）。ディレクトリ名に使われます。  
  **Rules:** `^[A-Za-z0-9._-]+$` and must not be `.` or `..` (no `/`).

- **run-id**  
  **EN:** An identifier for one review run under a given `scope-id`.  
  **JA:** 同じ `scope-id` の中で「今回の実行」を区別する識別子。  
  **Rules:** `^[A-Za-z0-9._-]+$` and must not be `.` or `..` (no `/`).

- **SoT (`SOT`)**  
  **EN:** “Source of Truth” for the expected behavior: ticket/spec/rules/docs. Required by review scripts.  
  **JA:** 期待される挙動の根拠（チケット/仕様/ルール/ドキュメント）。レビューでは必須です。

- **Tests (`TESTS`)**  
  **EN:** What you ran (or didn’t) and why. Required by review scripts.  
  **JA:** 実行したテスト（または未実行の理由）。レビューでは必須です。

- **7-1 / 7-2**  
  **EN:** `review-parallel` creates facet fragments (7-1). `pr-review` aggregates fragments into a single decision (7-2).  
  **JA:** `review-parallel` が観点別フラグメントを作る（7-1）。`pr-review` が集約して結論を出す（7-2）。

## Output layout / 出力レイアウト

**EN:** All review artifacts are written under the *target repository root* (the repo you are reviewing):  
**JA:** 全てのレビュー成果物は「レビュー対象リポジトリ」のルート配下に書き込みます:

- `docs/.reviews/schemas/`
  - `review-fragment.schema.json`
  - `pr-review.schema.json`
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/`
  - `diff-summary.txt` (from 7-1, unless overridden)
  - `<facet-slug>.json` (7-1 fragments)
  - `code-review.json` (optional overall fragment)
  - `aggregate/pr-review.json` (7-2 output)
  - `../.current_run` (tracks the most recent `run-id` for that `scope-id`)

## Installation / インストール

**EN:** Install into your Codex skills directory:  
**JA:** Codex の skills ディレクトリへインストールします:

```bash
./scripts/install.sh
```

**EN:** Options (see `./scripts/install.sh --help` for the latest):  
**JA:** オプション（詳細は `./scripts/install.sh --help` を参照）:
- `--dest <skills-dir>`: destination directory (default: `${CODEX_HOME:-$HOME/.codex}/skills`)
- `--link`: install via symlinks instead of copying
- `--dry-run`: print the plan and perform no writes

## Quick start / クイックスタート

**EN:** In the repository you want to review (must be a git repo):  
**JA:** レビュー対象リポジトリ内で実行します（git repo必須）:

```bash
export SOT='- <ticket/spec/rules>'
export TESTS='- <ran / not run>'

# 7-1: parallel facets (writes fragments + diff summary)
"$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" demo-scope

# 7-2: aggregate (uses diff summary + fragments only)
bash "$HOME/.codex/skills/pr-review (impl)/scripts/run_pr_review.sh" demo-scope
```

## Defaults and customization / デフォルトと調整

**EN:** Each script has its own defaults (model/effort). Override via environment variables.  
**JA:** デフォルト（モデル/推論強度など）はスクリプトごとに設定されています。環境変数で上書きしてください。

Defaults (as of this commit; confirm via `--dry-run`) / デフォルト（このcommit時点。`--dry-run` で確認）:
- `review-parallel`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=high`
- `code-review`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=xhigh`
- `pr-review`: `MODEL=gpt-5.2`, `REASONING_EFFORT=xhigh`

Examples / 例:

```bash
MODEL=gpt-5.2-codex REASONING_EFFORT=high \
  "$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" demo-scope
```

Notes / 注意:
- **EN:** `review-parallel` runs multiple facets; higher effort increases latency and usage across all facets.  
  **JA:** `review-parallel` は複数facetを回すため、推論強度を上げると時間/消費が増えやすいです。
- **EN:** A practical pattern is: start with `high`, then rerun only the weak/uncertain facet(s) with `xhigh`.  
  **JA:** まず `high` で回し、不十分なfacetだけ `xhigh` で再実行する運用が実用的です。

## Script reference / スクリプト仕様

### `review-parallel`: `run_review_parallel.sh` (7-1)

**EN:** Generates per-facet review fragments (JSON) and a diff summary; updates `.current_run` only after success.  
**JA:** 観点別レビューのJSONフラグメントと差分サマリを生成し、成功時のみ `.current_run` を更新します。

Run / 実行:

```bash
SOT="..." TESTS="..." \
  "$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" <scope-id> [run-id] [--dry-run]
```

Args / 引数:
- `<scope-id>`: required / 必須
- `[run-id]`: optional / 任意（未指定時は `RUN_ID` や `.current_run` を参照し、なければ timestamp 生成）
- `--dry-run`: preflight only; no writes. Exits `0` if ready; `1` if insufficient.  
  事前チェックのみ（書き込みなし）。準備OKなら `0`、不足があれば `1`。
  **EN:** `--dry-run` can be placed anywhere in the argv.  
  **JA:** `--dry-run` はどこに置いても構いません。
  **EN:** Only `--dry-run` is supported; unknown `--foo` will error.  
  **JA:** 対応するフラグは基本 `--dry-run` のみで、未知の `--foo` はエラーになります。

Diff selection / 差分の選び方:
- **EN:** `DIFF_MODE=auto` prefers *staged diff* when non-empty; unstaged changes are ignored in that case.  
  **JA:** `DIFF_MODE=auto` は staged が空でなければ staged 優先（未ステージ差分は落ちます）。
- **EN:** Use `DIFF_MODE=worktree` to include unstaged changes.  
  **JA:** 未ステージ差分も含めたい場合は `DIFF_MODE=worktree` を使ってください。
- **EN:** If you need to include untracked files, consider `git add -N .` before diffing.  
  **JA:** untracked を含めたい場合は `git add -N .` を検討してください。

Supported env / 対応env（概要）:
- Required / 必須: `SOT`, `TESTS`
- Optional / 任意（詳細はスクリプトの `Optional env:` を参照）:
  - `MODEL`, `REASONING_EFFORT`
  - `DIFF_MODE`, `DIFF_FILE`, `STRICT_STAGED`
  - `VALIDATE` (default `1`), `FORMAT_JSON` (default `1`)
  - `EXEC_TIMEOUT_SEC`, `CODEX_BIN`, `SCHEMA_PATH`, ...

Outputs / 出力:
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/<facet>.json`
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/diff-summary.txt` (default)

### `review-parallel`: `validate_review_fragments.py`

**EN:** Validates fragment JSONs in a run, and can rewrite them with pretty formatting.  
**JA:** run配下のフラグメントJSONを検証し、必要なら整形（pretty）で書き直します。

Run / 実行:

```bash
python3 "$HOME/.codex/skills/review-parallel (impl)/scripts/validate_review_fragments.py" \
  <scope-id> [run-id] --format
```

Key options / 主なオプション:
- `--facets <csv>`: validate only selected facets / 指定facetのみ検証
- `--schema <path>`: schema path / スキーマパス
- `--extra-file <path> --extra-slug <slug>`: validate an extra fragment (e.g. `code-review.json`)  
  追加フラグメント（例: `code-review.json`）も検証
- `--format`: rewrite validated JSON with indent=2 / 検証OKのJSONを整形して書き直す

### `code-review`: `run_code_review.sh` (Single / overall fragment)

**EN:** Produces one overall review fragment as JSON (`code-review.json`).  
**JA:** 全体レビューを1つのJSONフラグメント（`code-review.json`）として出力します。

Run / 実行:

```bash
SOT="..." TESTS="..." \
  "$HOME/.codex/skills/code-review (impl)/scripts/run_code_review.sh" <scope-id> [run-id] [--dry-run]
```

Notes / 注意:
- **EN:** `--dry-run` can be placed anywhere in the argv; unknown `--foo` will error.  
  **JA:** `--dry-run` はどこに置いてもOK、未知の `--foo` はエラーになります。
- **EN:** Uses `DIFF_MODE=auto` (staged preferred) by default; see `review-parallel` notes.  
  **JA:** 既定は `DIFF_MODE=auto`（staged優先）です。
- **EN:** Validates and (optionally) pretty-formats output when `VALIDATE=1`.  
  **JA:** `VALIDATE=1` のとき検証し、必要なら整形します。

Output / 出力:
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/code-review.json`

### `pr-review`: `run_pr_review.sh` (7-2)

**EN:** Aggregates 7-1 fragments into a single PR-level JSON decision. Does not re-review the full diff.  
**JA:** 7-1のフラグメントを集約し、PRレベルの結論JSONを出します。diff全文は再レビューしません。

Run / 実行:

```bash
SOT="..." TESTS="..." \
  bash "$HOME/.codex/skills/pr-review (impl)/scripts/run_pr_review.sh" <scope-id> [run-id] [--dry-run]
```

Requirements / 要件:
- **EN:** The run directory must already exist and contain all fixed facets + a diff summary.  
  **JA:** runディレクトリが存在し、固定6facet + diff summary が揃っている必要があります。
- **EN:** If `run-id` is omitted, `.current_run` must exist (no auto-generation).  
  **JA:** `run-id` 省略時は `.current_run` が必須（自動生成はしません）。
- **EN:** `python3` is always required for `pr-review` (it reads fragments and normalizes output).  
  **JA:** `pr-review` は常に `python3` が必要です（フラグメント読込・出力整形のため）。

Diff summary / 差分サマリ:
- **EN:** Provide via `DIFF_SUMMARY_FILE` or `DIFF_STAT`, otherwise it uses `diff-summary.txt` under the run directory.  
  **JA:** `DIFF_SUMMARY_FILE` または `DIFF_STAT` で渡すか、run配下の `diff-summary.txt` を使います。

Output / 出力:
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/aggregate/pr-review.json`

### `review-parallel`: `ensure_review_schemas.sh`

**EN:** Creates schema files in the target repo if missing (does not overwrite).  
**JA:** 対象リポジトリにスキーマが無ければ生成します（既存は上書きしません）。

Files / 生成物:
- `docs/.reviews/schemas/review-fragment.schema.json`
- `docs/.reviews/schemas/pr-review.schema.json`

## Troubleshooting / 典型トラブル

- **Diff is empty / Diff is empty (staged and worktree)**  
  **EN:** You may be running with no staged/unstaged changes. Stage changes or set `DIFF_MODE=worktree`.  
  **JA:** staged/未ステージの差分が無い可能性があります。ステージするか `DIFF_MODE=worktree` を使ってください。

- **`DIFF_MODE=auto` ignores unstaged changes**  
  **EN:** This is by design (staged preferred). Use `DIFF_MODE=worktree`.  
  **JA:** 仕様です（staged優先）。`DIFF_MODE=worktree` を使ってください。

- **`STRICT_STAGED=1 and staged diff is empty`**  
  **EN:** You forced staged-only review but nothing is staged. Either stage changes or set `STRICT_STAGED=0`.  
  **JA:** staged-only を強制しましたが staged が空です。ステージするか `STRICT_STAGED=0` にしてください。

- **Invalid scope-id / run-id**  
  **EN:** Only `A-Za-z0-9._-` are allowed (and not `.`/`..`).  
  **JA:** `A-Za-z0-9._-` のみ許可（`.`/`..` 禁止）です。

- **`python3 not found`**  
  **EN:** Install Python 3, or set `VALIDATE=0` where supported. (`pr-review` always needs Python.)  
  **JA:** Python3 を用意するか、可能な箇所では `VALIDATE=0` を検討してください（`pr-review` は常に必要）。
