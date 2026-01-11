# Skilled-Reviews Wiki（日本語）

English: `docs/wiki_en.md`

## 目的

同梱スクリプトを運用するための、人間向けリファレンスです（必要入力・出力先・調整できる設定など）。

正（Source of truth）: スクリプトが出力する `Usage:` / `Optional env:` が正です（wikiは追随が遅れる可能性があります）。

## 用語

- **scope-id**
  - 「何をレビューしているか」を表す識別子（チケット/PR等）。ディレクトリ名に使われます。
  - ルール: `^[A-Za-z0-9._-]+$` に一致し、`.` / `..` は禁止（`/` 不許可）。
- **run-id**
  - 同じ `scope-id` の中で「今回の実行」を区別する識別子。
  - ルール: `^[A-Za-z0-9._-]+$` に一致し、`.` / `..` は禁止（`/` 不許可）。
- **SoT (`SOT`)**
  - 期待される挙動の根拠（チケット/仕様/ルール/ドキュメント）。レビューでは必須です。
- **Tests (`TESTS`)**
  - 実行したテスト（または未実行の理由）。レビューでは必須です。
- **7-1 / 7-2**
  - `review-parallel` が観点別フラグメントを作る（7-1）。
  - `pr-review` がフラグメントを集約して結論を出す（7-2）。

## 出力レイアウト

全てのレビュー成果物は「レビュー対象リポジトリ」のルート配下に書き込みます:

- `docs/.reviews/schemas/`
  - `review-fragment.schema.json`
  - `pr-review.schema.json`
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/`
  - `diff-summary.txt`（通常は7-1が生成。上書き指定も可）
  - `<facet-slug>.json`（7-1のフラグメント）
  - `code-review.json`（任意の全体フラグメント）
  - `aggregate/pr-review.json`（7-2の出力）
  - `../.current_run`（その `scope-id` の最新 `run-id`）

## インストール

Codex の skills ディレクトリへインストールします:

```bash
./scripts/install.sh
```

オプション（詳細は `./scripts/install.sh --help` を参照）:
- `--dest <skills-dir>`: インストール先（default: `${CODEX_HOME:-$HOME/.codex}/skills`）
- `--link`: copyではなくsymlinkで配置
- `--dry-run`: 予定を表示し、書き込みはしない

## クイックスタート

レビュー対象リポジトリ内で実行します（git repo必須）:

```bash
export SOT='- <ticket/spec/rules>'
export TESTS='- <ran / not run>'

# 7-1: 観点別フラグメント作成（フラグメント + diff summary を出力）
"$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" demo-scope

# 7-2: 集約（diff summary + fragments のみ使用）
bash "$HOME/.codex/skills/pr-review (impl)/scripts/run_pr_review.sh" demo-scope
```

## デフォルトと調整

デフォルト（モデル/推論強度など）はスクリプトごとに設定されています。環境変数で上書きしてください。

デフォルト（このrepo時点。`--dry-run` で確認）:
- `review-parallel`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=high`
- `code-review`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=xhigh`
- `pr-review`: `MODEL=gpt-5.2`, `REASONING_EFFORT=xhigh`

例:

```bash
MODEL=gpt-5.2-codex REASONING_EFFORT=high \
  "$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" demo-scope
```

注意:
- `review-parallel` は複数facetを回すため、推論強度を上げると時間/消費が増えやすいです。
- 実用的には「まず `high` で回し、不十分なfacetだけ `xhigh` で再実行」が手堅いです。

## スクリプト仕様

### `review-parallel`: `run_review_parallel.sh`（7-1）

観点別レビューのJSONフラグメントと差分サマリを生成し、成功時のみ `.current_run` を更新します。

実行:

```bash
SOT="..." TESTS="..." \
  "$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" <scope-id> [run-id] [--dry-run]
```

引数:
- `<scope-id>`: 必須
- `[run-id]`: 任意（`RUN_ID` / `.current_run` を参照。なければ timestamp 生成）
- `--dry-run`: 事前チェックのみ（書き込みなし）。準備OKなら `0`、不足があれば `1`。
  - `--dry-run` はどこに置いても構いません。
  - 対応するフラグは基本 `--dry-run` のみで、未知の `--foo` はエラーになります。

差分の選び方:
- `DIFF_MODE=auto` は staged が空でなければ staged 優先（未ステージ差分は落ちます）。
- 未ステージ差分も含めたい場合は `DIFF_MODE=worktree` を使ってください。
- untracked を含めたい場合は `git add -N .` を検討してください。

対応env（概要）:
- 必須: `SOT`, `TESTS`
- 任意（詳細はスクリプトの `Optional env:` を参照）:
  - `MODEL`, `REASONING_EFFORT`
  - `DIFF_MODE`, `DIFF_FILE`, `STRICT_STAGED`
  - `VALIDATE`（default `1`）, `FORMAT_JSON`（default `1`）
  - `EXEC_TIMEOUT_SEC`, `CODEX_BIN`, `SCHEMA_PATH`, ...

出力:
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/<facet>.json`
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/diff-summary.txt`（default）

### `review-parallel`: `validate_review_fragments.py`

run配下のフラグメントJSONを検証し、必要なら整形（pretty）で書き直します。

実行:

```bash
python3 "$HOME/.codex/skills/review-parallel (impl)/scripts/validate_review_fragments.py" \
  <scope-id> [run-id] --format
```

主なオプション:
- `--facets <csv>`: 指定facetのみ検証
- `--schema <path>`: スキーマパス
- `--extra-file <path> --extra-slug <slug>`: 追加フラグメント（例: `code-review.json`）も検証
- `--format`: 検証OKのJSONを indent=2 で整形して書き直す

### `code-review`: `run_code_review.sh`（Single / 全体フラグメント）

全体レビューを1つのJSONフラグメント（`code-review.json`）として出力します。

実行:

```bash
SOT="..." TESTS="..." \
  "$HOME/.codex/skills/code-review (impl)/scripts/run_code_review.sh" <scope-id> [run-id] [--dry-run]
```

注意:
- `--dry-run` はどこに置いてもOK、未知の `--foo` はエラーになります。
- 既定は `DIFF_MODE=auto`（staged優先）です（`review-parallel` の注意も参照）。
- `VALIDATE=1` のとき検証し、必要なら整形します。

出力:
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/code-review.json`

### `pr-review`: `run_pr_review.sh`（7-2）

7-1のフラグメントを集約し、PRレベルの結論JSONを出します。diff全文は再レビューしません。

実行:

```bash
SOT="..." TESTS="..." \
  bash "$HOME/.codex/skills/pr-review (impl)/scripts/run_pr_review.sh" <scope-id> [run-id] [--dry-run]
```

要件:
- runディレクトリが存在し、固定6facet + diff summary が揃っている必要があります。
- `run-id` 省略時は `.current_run` が必須（自動生成はしません）。
- `pr-review` は常に `python3` が必要です（フラグメント読込・出力整形のため）。

差分サマリ:
- `DIFF_SUMMARY_FILE` または `DIFF_STAT` で渡すか、run配下の `diff-summary.txt` を使います。

出力:
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/aggregate/pr-review.json`

### `review-parallel`: `ensure_review_schemas.sh`

対象リポジトリにスキーマが無ければ生成します（既存は上書きしません）。

生成物:
- `docs/.reviews/schemas/review-fragment.schema.json`
- `docs/.reviews/schemas/pr-review.schema.json`

## 典型トラブル

- **Diff is empty / Diff is empty (staged and worktree)**
  - staged/未ステージの差分が無い可能性があります。ステージするか `DIFF_MODE=worktree` を使ってください。
- **`DIFF_MODE=auto` で未ステージ差分が落ちる**
  - 仕様です（staged優先）。`DIFF_MODE=worktree` を使ってください。
- **`STRICT_STAGED=1 and staged diff is empty`**
  - staged-only を強制しましたが staged が空です。ステージするか `STRICT_STAGED=0` にしてください。
- **Invalid scope-id / run-id**
  - `A-Za-z0-9._-` のみ許可（`.`/`..` 禁止）です。
- **`python3 not found`**
  - Python3 を用意するか、可能な箇所では `VALIDATE=0` を検討してください（`pr-review` は常に必要）。

