#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: install.sh [--dest <skills-dir>] [--link] [--dry-run]

Installs this repo's skills into the Codex skills directory.

Defaults:
  --dest: ${CODEX_HOME:-$HOME/.codex}/skills

Notes:
  - --link creates symlinks instead of copying.
  - --dry-run prints planned actions and performs no writes.
EOF
}

dry_run="0"
link_mode="0"
dest_skills=""

while (($#)); do
  case "$1" in
    --dry-run)
      dry_run="1"
      shift
      ;;
    --link)
      link_mode="1"
      shift
      ;;
    --dest)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --dest" >&2
        usage
        exit 1
      fi
      dest_skills="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "$dest_skills" ]]; then
  codex_home="${CODEX_HOME:-$HOME/.codex}"
  dest_skills="${codex_home}/skills"
fi

skills=(
  "impl"
  "implement-cycle"
  "review-cycle (impl)"
  "review-parallel (impl)"
  "code-review (impl)"
  "pr-review (impl)"
)

if [[ "$dry_run" == "1" ]]; then
  echo "--dry-run: no changes will be made" >&2
  printf -- "- repo_root: %s\n" "$repo_root" >&2
  printf -- "- dest_skills: %s\n" "$dest_skills" >&2
  printf -- "- link_mode: %s\n" "$link_mode" >&2
  printf -- "- skills:\n" >&2
  for s in "${skills[@]}"; do
    printf -- "  - %s\n" "$s" >&2
  done
  exit 0
fi

mkdir -p "$dest_skills"

if [[ "$link_mode" == "1" ]]; then
  for s in "${skills[@]}"; do
    src="${repo_root}/${s}"
    dst="${dest_skills}/${s}"
    if [[ ! -d "$src" ]]; then
      echo "Source skill dir not found: $src" >&2
      exit 1
    fi
    if [[ -e "$dst" && ! -L "$dst" ]]; then
      echo "Destination exists and is not a symlink: $dst" >&2
      echo "Remove it manually or install without --link." >&2
      exit 1
    fi
    ln -sfn "$src" "$dst"
  done
  echo "Installed (symlinked) into: $dest_skills" >&2
  exit 0
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync not found; install rsync or use --link" >&2
  exit 1
fi

rsync_flags=(
  -a
  --exclude=.DS_Store
  --exclude=__pycache__/
  --exclude=*.pyc
  --exclude=*.pyo
)

for s in "${skills[@]}"; do
  src="${repo_root}/${s}/"
  dst="${dest_skills}/${s}/"
  if [[ ! -d "${repo_root}/${s}" ]]; then
    echo "Source skill dir not found: ${repo_root}/${s}" >&2
    exit 1
  fi
  mkdir -p "$dst"
  rsync "${rsync_flags[@]}" "$src" "$dst"
done

echo "Installed (copied) into: $dest_skills" >&2

