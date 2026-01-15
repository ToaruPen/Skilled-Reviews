# Changelog

## v0.3.0 - 2026-01-15

- Unify all review JSON outputs to `review-v2.schema.json` (priority P0–P3, overall_correctness required, repo-relative code_location).
- Update `pr-review` aggregate output to the same v2 schema (breaking change vs `top_risks`/`required_fixes` format).
- Stop generating legacy schema files (`review-fragment.schema.json`, `pr-review.schema.json`) and standardize on v2 only.
- Enforce stricter validation rules via shared fragment validator (fail-closed Question, status↔overall_correctness consistency).

## v0.2.0 - 2026-01-12

- Add patch-based `implementation` skill (generates + validates + applies unified diffs).
- Move review artifacts under `.skilled-reviews/.reviews` (update scripts/docs).
- Update installer and self-test scripts.

## v0.1.0 - 2026-01-11

- Initial public release.
- Includes `impl` / `implement-cycle` and review-related skills (`review-cycle`, `review-parallel`, `code-review`, `pr-review`).
- Includes installer (`scripts/install.sh`), self test (`scripts/self_test.sh`), and GitHub Actions CI.
