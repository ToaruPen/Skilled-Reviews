---
name: code-review
description: >-
  言語・フレームワークを問わず、PR/コミット/差分のコードレビューを進めるための汎用ワークフロー。ユーザーが「コードレビュー」「PRレビュー」「差分レビュー」「コミット前の最終チェック」「品質/セキュリティ確認」を依頼したときに使う。プロジェクト固有のSoT/規約/CI/静的解析がある場合はそれを最優先し、情報不足は推測せず質問する。
---

# Code Review

## Overview

事故防止 → 要件整合 → 正しさ → テスト → セキュリティ → 保守性の順で、短時間でリスクを洗い出す。
軽量レビュー向け（手動実行OK・非決定論的な裁量を許容）。決定論的な運用が必要なら review-cycle を使う。
review-cycle と併用する場合は、code-review は補助、review-cycle を最終判断とする。
単独の軽量レビューとして使用可能。

## Workflow

1. 事前入力（差分/SoT/期待値/検証導線）を確認し、不足があれば止めて質問する。
2. 変更ファイル・差分量・影響領域（API/DB/認証/課金/暗号/インフラ等）を把握する。
3. ガードレール判定（Blocked/Question）を行う。
   - 出力形式の固定が必要な場合はサブコマンドに依存せず、`codex exec` に diff と PROMPT を pipe して渡す。
4. 可能ならプロジェクト標準の検証コマンドを実行する。
5. 詳細レビュー観点に沿って指摘を整理する。
6. 出力テンプレに沿って結論と次アクションを示す。

## Priority Order

1) プロジェクトの SoT / 規約 / CI（`AGENTS.md`、`CONTRIBUTING.md`、`README`、`docs/`、チケット/Issue/PR本文、CI設定）
2) ユーザーの依頼（review-only / fix可否 / commit/push可否）
3) 本スキルのチェック観点

## Inputs to Provide

- レビュー対象の差分（PR/ブランチ/コミット範囲/`uncommitted` のどれか）
- 要件SoT（チケット/Issue/仕様ドキュメント/PR本文など。最低1つ）
- レビューの期待値：
  - review-only（コメントのみ）
  - review + fix（直してよい）
  - review + commit（コミットまでやってよい）
  - review + commit + push（push までやってよい）
- 検証導線（標準コマンドと実行結果：build/test/lint/typecheck/security など）

不足がある場合は **Question** として止める。

## Diff Selection Priority

1) `git diff --staged`（コミット前の最終レビュー用）
2) `git diff`（未ステージのWIPレビュー）
3) `git show <commit>` / `git diff <base>...HEAD`（PR/コミットレビュー）

未ステージ差分のレビューも許可する。

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

- SoTと差分が結び付かない／無関係変更が混入 → Blocked
- 禁止領域・所有境界・データ取扱い・ライセンス等に抵触の疑い → Blocked（確証がなければ Question）
- 仕様が曖昧/未定義/矛盾 → Question（争点/選択肢/影響/推奨を短く）

## Review Focus (facet-aligned)

- Correctness and logic: normal-path behavior, invariants
- Edge cases and error handling: boundary/empty/failure handling
- Security and data safety: validation, auth, secrets, exposure
- Performance and resource use: hot paths, I/O, memory
- Tests and observability: coverage, regression, logging/metrics
- Design/consistency with project rules: layering, naming, responsibilities, maintainability

## Output Template

- Status: Blocked / Approved / Approved with nits / Question
- Blockers: 問題点 + 具体的な修正案（Blocked のとき必須）
- Questions: 追加情報が必要な点（Question のとき必須）
- Plan: Blocked / Question の場合は 3〜6 ステップで最短修正計画を提示
- Notes: 改善推奨（任意）
- Evidence: 確認した根拠（実行したコマンド/ログ/参照したSoT）、未実施項目
- Next: 次のアクション

## Optional JSON Output (review-cycle integration)

- Path: `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/code-review.json`
- Schema: `docs/.reviews/schemas/review-fragment.schema.json`
- Use `facet="Overall review (code-review)"` and `facet_slug="overall"`
- Generate via `codex exec --output-schema <schema> --output-last-message <path>` (JSON only)

## Scripts (optional)

- Single Review (review-cycle integration):
  `SOT="..." TESTS="..." "$HOME/.codex/skills/code-review (impl)/scripts/run_code_review.sh" <scope-id> [run-id] [--dry-run]`
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
- Output: `docs/.reviews/reviewed_scopes/<scope-id>/<run-id>/code-review.json`
- Execution timeout (harness): set command timeout to 1h; avoid EXEC_TIMEOUT_SEC unless a shorter, explicit limit is required.

## Status Rules

- Blocked: 修正必須
- Question: 情報不足で判断不能
- Approved: ブロッカーなし
- Approved with nits: 重大ではない改善提案のみ（仕様/安全性に影響しない）

## Commit/Push Policy

- commit/push は別作業として扱い、ユーザーの明示依頼がある場合のみ実行する。

## Language

- リポジトリの言語規約に従い、なければユーザーに合わせる。
