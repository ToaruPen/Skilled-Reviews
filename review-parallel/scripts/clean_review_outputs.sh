#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <scope-id> <run-id> [--dry-run]" >&2
  exit 1
fi

scope_id="$1"
run_id="$2"
dry_run="${3:-}"

if [[ ! "$scope_id" =~ ^[A-Za-z0-9._-]+$ || "$scope_id" == "." || "$scope_id" == ".." ]]; then
  echo "Invalid scope-id: $scope_id (allowed: [A-Za-z0-9._-]+, not '.' or '..')" >&2
  exit 1
fi

if [[ ! "$run_id" =~ ^[A-Za-z0-9._-]+$ || "$run_id" == "." || "$run_id" == ".." ]]; then
  echo "Invalid run-id: $run_id (allowed: [A-Za-z0-9._-]+, not '.' or '..')" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  echo "Not in a git repository; cannot locate repo root." >&2
  exit 1
fi

dir="${repo_root}/.skilled-reviews/.reviews/reviewed_scopes/${scope_id}/${run_id}"
if [[ ! -d "$dir" ]]; then
  exit 0
fi

shopt -s nullglob
json_files=("$dir"/*.json)

if [[ "$dry_run" == "--dry-run" ]]; then
  printf '%s\n' "${json_files[@]}"
  exit 0
fi

if (( ${#json_files[@]} == 0 )); then
  exit 0
fi
rm -f "${json_files[@]}"
