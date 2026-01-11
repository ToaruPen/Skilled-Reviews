# Skilled-Review

Codex CLI の `impl`（= `implement-cycle`）と review 関連スキル（`review-cycle` / `review-parallel` / `code-review` / `pr-review`）および実行スクリプトをまとめたリポジトリです。

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
- `codex` CLI（実際にレビューJSONを生成する場合）

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

主なトグル:
- `--dry-run`: 事前チェックのみ（no-write）。可能なら `exit 0`、不足があれば `exit 1`。
- `VALIDATE=1`（default）: JSON出力を検証（壊れ検知）。
- `FORMAT_JSON=1`（default）: JSONを人間向けに整形（indent=2）。

## 出力先

レビュー対象リポジトリのルート配下に書き込みます:
- `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/...`

`scope-id` / `run-id` は `^[A-Za-z0-9._-]+$` かつ `.`/`..` は禁止（`/` 不許可）。

## 自己テスト

```bash
./scripts/self_test.sh
```

`codex` バイナリはスタブで代替するため、ローカル環境に `codex` がなくても実行できます（`bash`/`git`/`python3` は必要）。

## CI

GitHub Actions で `scripts/self_test.sh` を実行します: `.github/workflows/ci.yml`
