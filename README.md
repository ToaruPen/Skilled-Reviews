# Skilled-Reviews

A repository bundling Codex CLI `impl` (alias of `implement-cycle`) plus review-related skills (`review-cycle`, `review-parallel`, `code-review`, `pr-review`) and their helper scripts.

Codex CLI の `impl`（`implement-cycle` の alias）と、review 関連スキル（`review-cycle` / `review-parallel` / `code-review` / `pr-review`）および補助スクリプトをまとめたリポジトリです。

## Docs / ドキュメント

- `docs/wiki_en.md` (English: args/env defaults, outputs, troubleshooting)
- `docs/wiki_ja.md`（日本語: 引数・env・出力先・トラブルシュート）

## Included skills / 含まれるスキル

- `impl` (alias)
- `implement-cycle`
- `review-cycle (impl)`
- `review-parallel (impl)`
- `code-review (impl)`
- `pr-review (impl)`

## Prerequisites / 前提

- `git`
- `bash`
- `python3`
- `codex` CLI (required only when you actually generate review JSON) / `codex` CLI（レビューJSONを実際に生成する場合のみ必要）

## Install / インストール

Copies these skills into `~/.codex/skills/` (or under `CODEX_HOME`).
`~/.codex/skills/`（または `CODEX_HOME` 配下）へコピーします。

```bash
./scripts/install.sh
```

## Usage (example) / 使い方（例）

```bash
export SOT='- <rules/specs/ticket>'
export TESTS='- <ran / not run>'

"$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" demo-scope --dry-run
```

## Key toggles / 主なトグル

- `--dry-run`: preflight only (no writes). `exit 0` when ready; `exit 1` when inputs/env are insufficient. / 事前チェックのみ（書き込みなし）。準備OKなら `exit 0`、不足があれば `exit 1`。
- `VALIDATE=1` (default): validate JSON outputs (detect breakage). / JSON出力を検証（壊れ検知）。
- `FORMAT_JSON=1` (default): pretty-format JSON outputs (indent=2). / JSONを整形（indent=2）。
- `MODEL` / `REASONING_EFFORT`: defaults are set per script; override them to your preferred model/effort. / デフォルトはスクリプトごとに設定されているので、好みのモデル/推論強度に上書きしてください。
  - `review-parallel`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=high`
  - `code-review`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=xhigh`
  - `pr-review`: `MODEL=gpt-5.2`, `REASONING_EFFORT=xhigh`

## Output location / 出力先

All scripts write under the target repository root:
全てのスクリプトは、対象リポジトリのルート配下に書き込みます:
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/...`

`scope-id` / `run-id` must match `^[A-Za-z0-9._-]+$` and must not be `.` or `..` (no `/`).
`scope-id` / `run-id` は `^[A-Za-z0-9._-]+$` に一致し、`.` / `..` は禁止です（`/` 不許可）。

## Self test / 自己テスト

```bash
./scripts/self_test.sh
```

The test stubs out the `codex` binary, so it can run without a local `codex` install (but still requires `bash`/`git`/`python3`).
テストでは `codex` バイナリをスタブに置き換えるため、ローカルに `codex` がなくても実行できます（ただし `bash`/`git`/`python3` は必要です）。

## CI

GitHub Actions runs `scripts/self_test.sh`: `.github/workflows/ci.yml`
GitHub Actions で `scripts/self_test.sh` を実行します: `.github/workflows/ci.yml`
