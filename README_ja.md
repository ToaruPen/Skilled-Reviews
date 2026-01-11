# Skilled-Reviews

[English](README.md) | [日本語](README_ja.md)

Codex CLI の `impl`（`implement-cycle` の alias）と、review 関連スキル（`review-cycle` / `review-parallel` / `code-review` / `pr-review`）および補助スクリプトをまとめたリポジトリです。

## ドキュメント

- `docs/wiki_ja.md`（日本語: 引数・env・出力先・トラブルシュート）
- `docs/wiki_en.md` (English: args/env defaults, outputs, troubleshooting)

## 含まれるスキル

- `impl`（alias）
- `implement-cycle`
- `review-cycle (impl)`
- `review-parallel (impl)`
- `code-review (impl)`
- `pr-review (impl)`

## 前提

- `git`
- `bash`
- `python3`
- `codex` CLI（レビューJSONを実際に生成する場合のみ必要）

## インストール

`~/.codex/skills/`（または `CODEX_HOME` 配下）へコピーします。

```bash
./scripts/install.sh
```

## 使い方（例）

```bash
export SOT='- <rules/specs/ticket>'
export TESTS='- <ran / not run>'

"$HOME/.codex/skills/review-parallel (impl)/scripts/run_review_parallel.sh" demo-scope --dry-run
```

## 切り替えオプション（Toggle options）

- `--dry-run`: 事前チェックのみ（書き込みなし）。準備OKなら `exit 0`、不足があれば `exit 1`。
- `VALIDATE=1`（default）: JSON出力を検証（壊れ検知）。
- `FORMAT_JSON=1`（default）: JSONを整形（indent=2）。
- `MODEL` / `REASONING_EFFORT`: デフォルトはスクリプトごとに設定されているので、好みのモデル/推論強度に上書きしてください。
  - `review-parallel`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=high`
  - `code-review`: `MODEL=gpt-5.2-codex`, `REASONING_EFFORT=xhigh`
  - `pr-review`: `MODEL=gpt-5.2`, `REASONING_EFFORT=xhigh`

## 出力先

全てのスクリプトは、対象リポジトリのルート配下に書き込みます:
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/...`

`scope-id` / `run-id` は `^[A-Za-z0-9._-]+$` に一致し、`.` / `..` は禁止です（`/` 不許可）。

## テスト

```bash
./scripts/self_test.sh
```

テストでは `codex` バイナリをスタブに置き換えるため、ローカルに `codex` がなくても実行できます（ただし `bash`/`git`/`python3` は必要です）。

## CI

GitHub Actions で `scripts/self_test.sh` を実行します: `.github/workflows/ci.yml`
