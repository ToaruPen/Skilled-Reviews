#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[1/3] shell syntax checks" >&2
while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find "$repo_root" -type f -name '*.sh' -print0)

echo "[1.5/3] install.sh dry-run" >&2
bash "$repo_root/scripts/install.sh" --dry-run >/dev/null
bash "$repo_root/scripts/install.sh" --dry-run --link >/dev/null

echo "[2/3] python syntax checks" >&2
python3 -m py_compile "$repo_root/review-parallel (impl)/scripts/validate_review_fragments.py"

echo "[3/3] integration smoke test (stub codex)" >&2

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

cd "$tmp"
git init -q
git config user.email test@example.com
git config user.name test

echo "hello" > a.txt
git add a.txt
git commit -q -m "init"

echo "world" >> a.txt
git add a.txt # staged diff exists

fake_codex="$tmp/fake_codex"
cat >"$fake_codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1-}" != "exec" ]]; then
  echo "Usage: fake_codex exec ..." >&2
  exit 2
fi
shift

out=""
while (($#)); do
  case "$1" in
    --output-last-message)
      out="$2"
      shift 2
      ;;
    --output-last-message=*)
      out="${1#*=}"
      shift
      ;;
    --output-schema)
      shift 2
      ;;
    --output-schema=*)
      shift
      ;;
    --sandbox|-m|-c)
      shift 2
      ;;
    -)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -z "$out" ]]; then
  echo "missing --output-last-message" >&2
  exit 2
fi

input="$(cat)"
slug="$(printf '%s\n' "$input" | awk -F': ' '/^Facet-Slug: / {print $2; exit}')"
if [[ -n "$slug" ]]; then
  facet="$slug"
  if [[ "$slug" == "overall" ]]; then
    facet="Overall review (code-review)"
  fi
  printf '{"facet":"%s","facet_slug":"%s","status":"Approved","findings":[],"uncertainty":[],"questions":[]}\n' "$facet" "$slug" > "$out"
  exit 0
fi

scope="$(printf '%s\n' "$input" | awk -F': ' '/^- Scope-id: / {print $2; exit}')"
if [[ -z "$scope" ]]; then
  scope="unknown"
fi

cat >"$out" <<JSON
{"scope_id":"$scope","status":"Approved with nits","top_risks":[],"required_fixes":[],"optional_nits":["stub output"],"assumptions":[],"questions":[],"facet_coverage":[{"facet_slug":"correctness","status":"Approved"},{"facet_slug":"edge-cases","status":"Approved"},{"facet_slug":"security","status":"Approved"},{"facet_slug":"performance","status":"Approved"},{"facet_slug":"tests-observability","status":"Approved"},{"facet_slug":"design-consistency","status":"Approved"}]}
JSON
SH
chmod +x "$fake_codex"

export SOT='- stub sot'
export TESTS='- not run'
export CODEX_BIN="$fake_codex"

scope_id="skills-json-format"
run_id="testrun"

"$repo_root/review-parallel (impl)/scripts/run_review_parallel.sh" "$scope_id" "$run_id" >/dev/null
"$repo_root/code-review (impl)/scripts/run_code_review.sh" "$scope_id" "$run_id" >/dev/null
bash "$repo_root/pr-review (impl)/scripts/run_pr_review.sh" "$scope_id" "$run_id" >/dev/null

run_dir="$tmp/docs/.reviews/reviewed_scopes/$scope_id/$run_id"
python3 - "$run_dir" <<'PY'
import json
import os
import sys

run_dir = sys.argv[1]
paths = [
    os.path.join(run_dir, "correctness.json"),
    os.path.join(run_dir, "code-review.json"),
    os.path.join(run_dir, "aggregate", "pr-review.json"),
]

for path in paths:
    with open(path, "r", encoding="utf-8") as fh:
        json.load(fh)

print("OK: integration smoke test passed")
PY
