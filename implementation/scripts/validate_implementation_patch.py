#!/usr/bin/env python3
import argparse
import ast
import fnmatch
import os
import re
import subprocess
import sys
from typing import List, Tuple


def normalize_repo_relpath(value: str) -> str:
    value = value.strip()
    while value.startswith("./"):
        value = value[2:]
    if value.startswith("/"):
        value = value[1:]
    return value


def _strip_toml_comment(line: str) -> str:
    in_string = False
    escape = False
    out = []
    for ch in line:
        if in_string:
            out.append(ch)
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            continue

        if ch == '"':
            in_string = True
            out.append(ch)
            continue

        if ch == "#":
            break

        out.append(ch)
    return "".join(out)


def _extract_toml_array(text: str, key: str) -> str:
    m = re.search(rf"(?m)^[ \t]*{re.escape(key)}[ \t]*=", text)
    if not m:
        raise ValueError(f"Missing required key: {key}")
    idx = m.end()
    while idx < len(text) and text[idx] in " \t":
        idx += 1
    if idx >= len(text) or text[idx] != "[":
        raise ValueError(f"{key} must be an array (expected '[' after '=')")

    depth = 0
    in_string = False
    escape = False
    start = idx
    for j in range(idx, len(text)):
        ch = text[j]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            continue

        if ch == '"':
            in_string = True
            continue

        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return text[start : j + 1]

    raise ValueError(f"Unterminated array for key: {key}")


def parse_policy(policy_path: str) -> Tuple[List[str], List[str]]:
    with open(policy_path, "r", encoding="utf-8") as fh:
        raw_lines = fh.readlines()
    text = "".join(_strip_toml_comment(line) for line in raw_lines)

    allow_raw = _extract_toml_array(text, "write_allow")
    deny_raw = _extract_toml_array(text, "write_deny")

    try:
        allow = ast.literal_eval(allow_raw)
        deny = ast.literal_eval(deny_raw)
    except Exception as exc:
        raise ValueError(f"Failed to parse policy arrays: {exc}") from exc

    if not isinstance(allow, list) or not all(isinstance(x, str) for x in allow):
        raise ValueError("write_allow must be an array of strings")
    if not isinstance(deny, list) or not all(isinstance(x, str) for x in deny):
        raise ValueError("write_deny must be an array of strings")

    allow = [normalize_repo_relpath(p) for p in allow if p.strip()]
    deny = [normalize_repo_relpath(p) for p in deny if p.strip()]

    if not allow:
        raise ValueError("write_allow must not be empty (fail-closed)")

    return allow, deny


def run_git(repo_root: str, args: List[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args],
        cwd=repo_root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def parse_numstat(numstat: str) -> Tuple[List[Tuple[str, str, str]], int, int, bool]:
    entries = []
    lines_changed = 0
    binary_change = False

    for line in [ln for ln in numstat.splitlines() if ln.strip()]:
        parts = line.split("\t", 2)
        if len(parts) != 3:
            raise ValueError(f"Unexpected --numstat line: {line!r}")
        added_s, deleted_s, path = parts[0], parts[1], parts[2]
        entries.append((added_s, deleted_s, path))
        if added_s == "-" or deleted_s == "-":
            binary_change = True
            continue
        try:
            lines_changed += int(added_s) + int(deleted_s)
        except ValueError:
            raise ValueError(f"Non-numeric --numstat values: {line!r}")

    files_changed = len(entries)
    return entries, lines_changed, files_changed, binary_change


def subsystem_of(path: str) -> str:
    path = normalize_repo_relpath(path)
    if "/" not in path:
        return "root"
    return path.split("/", 1)[0]


def matches_any(path: str, patterns: List[str]) -> bool:
    path = normalize_repo_relpath(path)
    for pat in patterns:
        if fnmatch.fnmatchcase(path, pat):
            return True
    return False


def disallowed_git_mode_in_patch(patch_text: str) -> Tuple[str, str]:
    """
    Return (path, mode) if the patch touches a disallowed git file mode.

    Rationale: `git apply --summary` does not report mode for symlink/submodule *modifications*,
    so we must inspect the patch text for `index ... <mode>` lines.
    """
    current_path = ""
    for raw_line in patch_text.splitlines():
        line = raw_line.strip("\n")
        if line.startswith("diff --git "):
            # Example: diff --git a/path b/path
            parts = line.split()
            if len(parts) >= 4:
                b_path = parts[3]
                if b_path.startswith("b/"):
                    b_path = b_path[2:]
                current_path = normalize_repo_relpath(b_path)
            continue

        if line.startswith("index "):
            m = re.match(r"^index [0-9a-f]{7,40}\.\.[0-9a-f]{7,40} ([0-9]{6})$", line)
            if not m:
                continue
            mode = m.group(1)
            if mode in {"120000", "160000"}:
                return current_path or "<unknown>", mode
    return "", ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", required=True)
    ap.add_argument("--patch", required=True)
    ap.add_argument("--policy", required=True)
    ap.add_argument("--allow-large-patch", action="store_true")
    args = ap.parse_args()

    repo_root = os.path.abspath(args.repo_root)
    patch_path = os.path.abspath(args.patch)
    policy_path = os.path.abspath(args.policy)

    if not os.path.isdir(repo_root):
        print(f"repo_root is not a directory: {repo_root}", file=sys.stderr)
        return 1
    if not os.path.isfile(patch_path) or os.path.getsize(patch_path) == 0:
        print(f"patch is missing or empty: {patch_path}", file=sys.stderr)
        return 1
    if not os.path.isfile(policy_path):
        print(f"policy file not found: {policy_path}", file=sys.stderr)
        return 1

    try:
        allow, deny = parse_policy(policy_path)
    except Exception as exc:
        print(f"Invalid policy: {exc}", file=sys.stderr)
        return 1

    with open(patch_path, "r", encoding="utf-8", errors="replace") as fh:
        patch_text = fh.read()

    # Enforce v1 disallows that are not reliably visible via `git apply --summary`.
    blocked_path, blocked_mode = disallowed_git_mode_in_patch(patch_text)
    if blocked_mode == "120000":
        print(f"Blocked: symlink detected in patch (mode 120000): {blocked_path}", file=sys.stderr)
        return 1
    if blocked_mode == "160000":
        print(f"Blocked: submodule gitlink detected in patch (mode 160000): {blocked_path}", file=sys.stderr)
        return 1

    # Patch must be applyable (structure + context).
    chk = run_git(repo_root, ["apply", "--check", patch_path])
    if chk.returncode != 0:
        print("git apply --check failed:", file=sys.stderr)
        sys.stderr.write(chk.stderr)
        return 1

    summary = run_git(repo_root, ["apply", "--summary", patch_path])
    if summary.returncode != 0:
        print("git apply --summary failed:", file=sys.stderr)
        sys.stderr.write(summary.stderr)
        return 1

    numstat = run_git(repo_root, ["apply", "--numstat", patch_path])
    if numstat.returncode != 0:
        print("git apply --numstat failed:", file=sys.stderr)
        sys.stderr.write(numstat.stderr)
        return 1

    entries, lines_changed, files_changed, binary_change = parse_numstat(numstat.stdout)
    subsystems = sorted({subsystem_of(path) for _, _, path in entries})

    # Enforce v1 disallows.
    if "GIT binary patch" in patch_text or "Binary files" in patch_text:
        binary_change = True

    if binary_change:
        print("Blocked: binary change detected (v1 forbids binary patches)", file=sys.stderr)
        return 1

    for line in [ln for ln in summary.stdout.splitlines() if ln.strip()]:
        s = line.lstrip()
        if s.startswith("rename "):
            print(f"Blocked: rename detected: {s}", file=sys.stderr)
            return 1
        if s.startswith("copy "):
            print(f"Blocked: copy detected: {s}", file=sys.stderr)
            return 1
        if s.startswith("delete mode "):
            print(f"Blocked: delete detected: {s}", file=sys.stderr)
            return 1
        if s.startswith("mode change "):
            print(f"Blocked: mode change detected: {s}", file=sys.stderr)
            return 1
        if s.startswith("create mode "):
            m = re.match(r"create mode ([0-9]{6}) ", s)
            if not m:
                print(f"Blocked: unexpected create mode format: {s}", file=sys.stderr)
                return 1
            mode = m.group(1)
            if mode != "100644":
                print(f"Blocked: new file mode must be 100644 (got {mode})", file=sys.stderr)
                return 1

    # Allow/deny (deny overrides allow).
    touched_paths = [normalize_repo_relpath(path) for _, _, path in entries]
    for path in touched_paths:
        if path == ".gitmodules":
            print("Blocked: .gitmodules touched (v1 forbids submodules)", file=sys.stderr)
            return 1
        if matches_any(path, deny):
            print(f"Blocked: path is denied by policy: {path}", file=sys.stderr)
            return 1
        if not matches_any(path, allow):
            print(f"Blocked: path is not allowed by policy: {path}", file=sys.stderr)
            return 1

    # Large patch guard.
    large = lines_changed > 600 or files_changed > 15 or len(subsystems) >= 3 or binary_change
    if large and not args.allow_large_patch:
        print(
            "Blocked: patch exceeds auto-apply thresholds "
            f"(lines_changed={lines_changed}, files_changed={files_changed}, subsystems={len(subsystems)}) "
            "Use ALLOW_LARGE_PATCH=1 to override.",
            file=sys.stderr,
        )
        return 1

    # Echo a short summary (stderr) for traceability.
    print(
        "Patch OK:"
        f" lines_changed={lines_changed}"
        f" files_changed={files_changed}"
        f" subsystems={len(subsystems)}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
