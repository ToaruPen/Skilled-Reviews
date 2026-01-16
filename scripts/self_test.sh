#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pycache_prefix="${repo_root}/__pycache__"
mkdir -p "$pycache_prefix"
export PYTHONPYCACHEPREFIX="$pycache_prefix"

echo "[1/3] shell syntax checks" >&2
while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find "$repo_root" -type f -name '*.sh' -print0)

echo "[1.5/3] install.sh dry-run" >&2
bash "$repo_root/scripts/install.sh" --dry-run >/dev/null
bash "$repo_root/scripts/install.sh" --dry-run --link >/dev/null

echo "[1.6/3] drift checks" >&2
if ! cmp -s "$repo_root/code-review/scripts/ensure_review_schemas.sh" "$repo_root/review-parallel/scripts/ensure_review_schemas.sh"; then
  echo "ERROR: drift detected: ensure_review_schemas.sh (code-review vs review-parallel)" >&2
  exit 1
fi
if ! cmp -s "$repo_root/code-review/scripts/review-v2-policy.md" "$repo_root/review-parallel/scripts/review-v2-policy.md"; then
  echo "ERROR: drift detected: review-v2-policy.md (code-review vs review-parallel)" >&2
  exit 1
fi
if ! cmp -s "$repo_root/code-review/scripts/validate_review_fragments.py" "$repo_root/review-parallel/scripts/validate_review_fragments.py"; then
  echo "ERROR: drift detected: validate_review_fragments.py (code-review vs review-parallel)" >&2
  exit 1
fi

echo "[2/3] python syntax checks" >&2
python3 -m py_compile "$repo_root/review-parallel/scripts/validate_review_fragments.py"
python3 -m py_compile "$repo_root/code-review/scripts/validate_review_fragments.py"
python3 -m py_compile "$repo_root/implementation/scripts/validate_implementation_patch.py"
python3 -m py_compile "$repo_root/implementation/scripts/extract_review_feedback.py"

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
if printf '%s\n' "$input" | grep -q '^You are an implementation agent operating in a git repository\.'; then
  if [[ -n "${EXPECT_REVIEW_ISSUE:-}" ]]; then
    if ! printf '%s\n' "$input" | grep -Fq "$EXPECT_REVIEW_ISSUE"; then
      echo "missing expected review issue in prompt: $EXPECT_REVIEW_ISSUE" >&2
      exit 3
    fi
    cat >"$out" <<'PATCH'
diff --git a/hello2.txt b/hello2.txt
new file mode 100644
index 0000000..4d638bc
--- /dev/null
+++ b/hello2.txt
@@ -0,0 +1 @@
+hello2
PATCH
    exit 0
  fi
  cat >"$out" <<'PATCH'
diff --git a/hello.txt b/hello.txt
new file mode 100644
index 0000000..ce01362
--- /dev/null
+++ b/hello.txt
@@ -0,0 +1 @@
+hello
PATCH
  exit 0
fi
slug="$(printf '%s\n' "$input" | awk -F': ' '/^Facet-Slug: / {print $2; exit}')"
if [[ -n "$slug" ]]; then
  facet="$slug"
  if [[ "$slug" == "overall" ]]; then
    facet="Overall review (code-review)"
  elif [[ "$slug" == "aggregate" ]]; then
    facet="PR-level aggregate"
  fi
  printf '{"schema_version":2,"facet":"%s","facet_slug":"%s","status":"Approved","findings":[],"questions":[],"uncertainty":[],"overall_correctness":"patch is correct","overall_explanation":"stub","overall_confidence_score":1}\n' "$facet" "$slug" > "$out"
  exit 0
fi

scope="$(printf '%s\n' "$input" | awk -F': ' '/^- Scope-id: / {print $2; exit}')"
if [[ -z "$scope" ]]; then
  scope="unknown"
fi

cat >"$out" <<JSON
{"schema_version":2,"scope_id":"$scope","facet":"PR-level aggregate","facet_slug":"aggregate","status":"Approved","findings":[],"questions":[],"uncertainty":[],"overall_correctness":"patch is correct","overall_explanation":"stub output","overall_confidence_score":1}
JSON
SH
chmod +x "$fake_codex"

export SOT='- stub sot'
export TESTS='- not run'
export CODEX_BIN="$fake_codex"

mkdir -p .skilled-reviews/.implementation
cat > .skilled-reviews/.implementation/impl-guardrails.toml <<'TOML'
write_allow = [
  "hello.txt",
  "hello2.txt",
]

write_deny = [
  ".skilled-reviews/**",
  ".git/**",
]
TOML

mkdir -p .skilled-reviews/.estimation
cat > .skilled-reviews/.estimation/impl_smoke.md <<'MD'
# impl smoke

- Create `hello.txt` with `hello`.
MD

ESTIMATION_FILE=".skilled-reviews/.estimation/impl_smoke.md" \
  "$repo_root/implementation/scripts/run_implementation.sh" impl-smoke testrun-impl >/dev/null

test -f hello.txt
test "$(cat hello.txt)" = "hello"

echo "[3.0/3] implementation review-feedback wiring test (stub codex)" >&2

cat > review.json <<'JSON'
{
  "schema_version": 2,
  "facet": "Overall review (code-review)",
  "facet_slug": "overall",
  "status": "Blocked",
  "overall_correctness": "patch is incorrect",
  "overall_explanation": "stub overall explanation",
  "overall_confidence_score": 1.0,
  "findings": [
    {
      "title": "[P0] MARKER_REVIEW_ISSUE",
      "body": "stub body",
      "confidence_score": 1.0,
      "priority": 0,
      "code_location": {
        "repo_relative_path": "a.txt",
        "line_range": {
          "start": 1,
          "end": 1
        }
      }
    }
  ],
  "questions": [],
  "uncertainty": []
}
JSON

export EXPECT_REVIEW_ISSUE="MARKER_REVIEW_ISSUE"

REVIEW_FILE="review.json" \
ESTIMATION_FILE=".skilled-reviews/.estimation/impl_smoke.md" \
  "$repo_root/implementation/scripts/run_implementation.sh" impl-smoke testrun-impl-review >/dev/null

unset EXPECT_REVIEW_ISSUE

test -f hello2.txt
test "$(cat hello2.txt)" = "hello2"

echo "[3.1/3] implementation guardrails negative tests" >&2

# Symlink patches must be blocked (v1 forbids symlinks).
symlink_repo="$tmp/symlink-guardrail"
mkdir -p "$symlink_repo"
cd "$symlink_repo"
git init -q
git config user.email test@example.com
git config user.name test

ln -s target-a link
git add link
git commit -q -m "add symlink"

rm link
ln -s target-b link
symlink_patch="${symlink_repo}/symlink.patch"
git diff --no-color > "$symlink_patch"
rm link
git checkout -q -- link

mkdir -p .skilled-reviews/.implementation
cat > .skilled-reviews/.implementation/impl-guardrails.toml <<'TOML'
write_allow = [
  "link",
]

write_deny = [
]
TOML

if python3 "$repo_root/implementation/scripts/validate_implementation_patch.py" \
  --repo-root "$symlink_repo" --patch "$symlink_patch" --policy "$symlink_repo/.skilled-reviews/.implementation/impl-guardrails.toml" \
  >/dev/null 2>&1; then
  echo "ERROR: expected symlink patch to be blocked by validator" >&2
  exit 1
fi

# Submodule (gitlink) patches must be blocked (v1 forbids submodules).
sub_guard="$tmp/submodule-guardrail"
sub_repo="$sub_guard/sub"
main_repo="$sub_guard/main"
mkdir -p "$sub_repo" "$main_repo"

cd "$sub_repo"
git init -q
git config user.email test@example.com
git config user.name test

echo v1 > file.txt
git add file.txt
git commit -q -m "v1"
commit_a="$(git rev-parse HEAD)"

echo v2 > file.txt
git add file.txt
git commit -q -m "v2"
commit_b="$(git rev-parse HEAD)"

cd "$main_repo"
git init -q
git config user.email test@example.com
git config user.name test

GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
  git submodule add -q "$sub_repo" submod

cd submod
git checkout -q "$commit_a"
cd ..
git add submod .gitmodules
git commit -q -m "add submodule at A"

cd submod
git checkout -q "$commit_b"
cd ..
submodule_patch="${sub_guard}/submodule.patch"
git diff --no-color > "$submodule_patch"

cd submod
git checkout -q "$commit_a"
cd ..

mkdir -p .skilled-reviews/.implementation
cat > .skilled-reviews/.implementation/impl-guardrails.toml <<'TOML'
write_allow = [
  "submod",
]

write_deny = [
]
TOML

if python3 "$repo_root/implementation/scripts/validate_implementation_patch.py" \
  --repo-root "$main_repo" --patch "$submodule_patch" --policy "$main_repo/.skilled-reviews/.implementation/impl-guardrails.toml" \
  >/dev/null 2>&1; then
  echo "ERROR: expected submodule patch to be blocked by validator" >&2
  exit 1
fi

cd "$tmp"

echo "world" >> a.txt
git add a.txt # staged diff exists

scope_id="skills-json-format"
run_id="testrun"

"$repo_root/review-parallel/scripts/run_review_parallel.sh" "$scope_id" "$run_id" >/dev/null
"$repo_root/code-review/scripts/run_code_review.sh" "$scope_id" "$run_id" >/dev/null
bash "$repo_root/pr-review/scripts/run_pr_review.sh" "$scope_id" "$run_id" >/dev/null

run_dir="$tmp/.skilled-reviews/.reviews/reviewed_scopes/$scope_id/$run_id"
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
