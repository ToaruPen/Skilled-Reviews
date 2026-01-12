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
- **見積もり (`ESTIMATION_FILE`)**
  - `implementation`（パッチ実装）で使う見積もり/実装計画ドキュメントのパス。
- **レビュー系スクリプト / スキル**
  - `code-review`（single）: 対象diffを1回レビューし、全体フラグメント `code-review.json` を出力（コード変更なし）。
  - `review-cycle`: 実装側のレビュー反復フロー。リスクに応じて single（`code-review`）/ parallel（`review-parallel` → `pr-review`）を選び、必要なら修正して再実行します。
  - `review-parallel`（parallel facets）: 固定6観点のフラグメント（`<facet-slug>.json`）+ `diff-summary.txt` を出力（コード変更なし）。
  - `pr-review`（aggregate）: `diff-summary.txt` + フラグメント（必要なら `code-review.json`）を集約し、結論 `aggregate/pr-review.json` を出力（diff全文は再レビューしません）。
- **実装系スクリプト / スキル**
  - `implementation`（patch-based）: `codex exec --sandbox read-only` で unified diff patch を生成し、repo-local のガードレールに合格した場合のみ `git apply` で適用します。

## 出力レイアウト

全てのレビュー成果物は「レビュー対象リポジトリ」のルート配下に書き込みます:

- `.skilled-reviews/.reviews/schemas/`
  - `review-fragment.schema.json`
  - `pr-review.schema.json`
- `.skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<run-id>/`
  - `diff-summary.txt`（通常は `review-parallel` が生成。上書き指定も可）
  - `<facet-slug>.json`（`review-parallel` のフラグメント）
  - `code-review.json`（任意の全体フラグメント）
  - `aggregate/pr-review.json`（`pr-review` の出力）
  - `../.current_run`（その `scope-id` の最新 `run-id`）

実装（`implementation`）の成果物も「対象リポジトリ」のルート配下に書き込みます:

- `.skilled-reviews/.implementation/impl-runs/<scope-id>/<run-id>/`
  - `raw.txt`（モデルの生出力）
  - `patch.diff`（抽出した unified diff patch）

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

# `review-parallel`: 観点別フラグメント作成（フラグメント + diff summary を出力）
"$HOME/.codex/skills/review-parallel/scripts/run_review_parallel.sh" demo-scope

# `pr-review`: 集約（diff summary + fragments のみ使用）
bash "$HOME/.codex/skills/pr-review/scripts/run_pr_review.sh" demo-scope
```

パッチ実装（対象repoにガードレール設定が必要）:

```bash
export SOT='- <ticket/spec/rules>'
export ESTIMATION_FILE='.skilled-reviews/.estimation/YYYY/MM/<scope>.md'

"$HOME/.codex/skills/implementation/scripts/run_implementation.sh" demo-scope --dry-run
```

## デフォルトと調整

デフォルト（モデル/推論強度など）はスクリプトごとに設定されています。環境変数で上書きしてください。

デフォルト（このrepo時点。`--dry-run` で確認）:
- `implementation`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=high`
- `review-parallel`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=high`
- `code-review`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=xhigh`
- `pr-review`: `MODEL=gpt-5.2`, `REASONING_EFFORT=xhigh`

例:

```bash
MODEL=gpt-5.2-codex REASONING_EFFORT=high \
  "$HOME/.codex/skills/review-parallel/scripts/run_review_parallel.sh" demo-scope
```

注意:
- `review-parallel` は複数facetを回すため、推論強度を上げると時間/消費が増えやすいです。
- 実用的には「まず `high` で回し、不十分なfacetだけ `xhigh` で再実行」が手堅いです。

## スクリプト仕様

### `review-parallel`: `run_review_parallel.sh`

観点別レビューのJSONフラグメントと差分サマリを生成し、成功時のみ `.current_run` を更新します。

実行:

```bash
SOT="..." TESTS="..." \
  "$HOME/.codex/skills/review-parallel/scripts/run_review_parallel.sh" <scope-id> [run-id] [--dry-run]
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
- `.skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<run-id>/<facet>.json`
- `.skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<run-id>/diff-summary.txt`（default）

### `review-parallel`: `validate_review_fragments.py`

run配下のフラグメントJSONを検証し、必要なら整形（pretty）で書き直します。

実行:

```bash
python3 "$HOME/.codex/skills/review-parallel/scripts/validate_review_fragments.py" \
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
  "$HOME/.codex/skills/code-review/scripts/run_code_review.sh" <scope-id> [run-id] [--dry-run]
```

注意:
- `--dry-run` はどこに置いてもOK、未知の `--foo` はエラーになります。
- 既定は `DIFF_MODE=auto`（staged優先）です（`review-parallel` の注意も参照）。
- `VALIDATE=1` のとき検証し、必要なら整形します。

出力:
- `.skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<run-id>/code-review.json`

### `pr-review`: `run_pr_review.sh`

`review-parallel` のフラグメントを集約し、PRレベルの結論JSONを出します。diff全文は再レビューしません。

実行:

```bash
SOT="..." TESTS="..." \
  bash "$HOME/.codex/skills/pr-review/scripts/run_pr_review.sh" <scope-id> [run-id] [--dry-run]
```

要件:
- runディレクトリが存在し、固定6facet + diff summary が揃っている必要があります。
- `run-id` 省略時は `.current_run` が必須（自動生成はしません）。
- `pr-review` は常に `python3` が必要です（フラグメント読込・出力整形のため）。

差分サマリ:
- `DIFF_SUMMARY_FILE` または `DIFF_STAT` で渡すか、run配下の `diff-summary.txt` を使います。

出力:
- `.skilled-reviews/.reviews/reviewed_scopes/<scope-id>/<run-id>/aggregate/pr-review.json`

### `implementation`: `run_implementation.sh`（パッチ実装）

`codex exec --sandbox read-only` で unified diff patch を生成し、repo-local のガードレールで検証した上で、許可される場合のみ `git apply` で適用します。

実行（対象repoルートで）:

```bash
SOT="..." ESTIMATION_FILE=".skilled-reviews/.estimation/..." \
  "$HOME/.codex/skills/implementation/scripts/run_implementation.sh" <scope-id> [run-id] [--dry-run]
```

注意:
- `.skilled-reviews/.implementation/impl-guardrails.toml`（repo-local policy）が必須です（gitignore推奨）。
- staged/未ステージ差分がある場合は中断します（スコープ混入防止）。
- `APPLY=0` で生成 + 検証のみ（適用しない）にできます。
- Blocked/Question の指摘修正を回す場合は `REVIEW_FILE=.skilled-reviews/.reviews/.../code-review.json`（または `pr-review.json`）を渡して修正パッチ生成に使えます。

### `implementation`: `validate_implementation_patch.py`

パッチをガードレールポリシー（および `git apply --check`）で検証します。

実行（対象repoルートで）:

```bash
python3 "$HOME/.codex/skills/implementation/scripts/validate_implementation_patch.py" \
  --repo-root . --patch <patch.diff> --policy .skilled-reviews/.implementation/impl-guardrails.toml
```

### `review-parallel`: `ensure_review_schemas.sh`

対象リポジトリにスキーマが無ければ生成します（既存は上書きしません）。

生成物:
- `.skilled-reviews/.reviews/schemas/review-fragment.schema.json`
- `.skilled-reviews/.reviews/schemas/pr-review.schema.json`

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
