#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any, Optional


def _clip(value: str, *, max_chars: int) -> str:
    value = value.strip()
    if len(value) <= max_chars:
        return value
    return value[: max_chars - 1].rstrip() + "…"


def _as_str(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return str(value)


_PRIORITY_PREFIX_RE = re.compile(r"^\[P[0-3]\]\s*")


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _strip_priority_prefix(title: str) -> str:
    title = title.strip()
    if not title:
        return ""
    return _PRIORITY_PREFIX_RE.sub("", title).strip()


def _priority_int(value: Any) -> Optional[int]:
    if isinstance(value, int) and not isinstance(value, bool):
        return value
    if isinstance(value, str):
        value = value.strip()
        if value.isdigit():
            try:
                return int(value)
            except ValueError:
                return None
    return None


def _format_location(code_location: Any) -> str:
    if not isinstance(code_location, dict):
        return ""
    path = _as_str(code_location.get("repo_relative_path")).strip()
    line_range = code_location.get("line_range")
    if not isinstance(line_range, dict):
        return path
    start = line_range.get("start")
    end = line_range.get("end")
    if path and isinstance(start, int) and isinstance(end, int):
        return f"{path}:{start}-{end}"
    return path


def _is_review_fragment(obj: Any) -> bool:
    return (
        isinstance(obj, dict)
        and isinstance(obj.get("facet"), str)
        and isinstance(obj.get("facet_slug"), str)
        and isinstance(obj.get("status"), str)
        and isinstance(obj.get("findings"), list)
        and isinstance(obj.get("questions"), list)
        and isinstance(obj.get("uncertainty"), list)
        and isinstance(obj.get("overall_correctness"), str)
        and isinstance(obj.get("overall_explanation"), str)
        and _is_number(obj.get("overall_confidence_score"))
    )


def _format_review_fragment(obj: dict[str, Any], *, max_findings: int) -> list[str]:
    lines: list[str] = []
    status = _as_str(obj.get("status")).strip()
    facet_slug = _as_str(obj.get("facet_slug")).strip()
    if facet_slug:
        lines.append(f"Facet: {facet_slug}")
    if status:
        lines.append(f"Status: {status}")

    findings = obj.get("findings") or []
    if isinstance(findings, list) and findings:
        lines.append("Findings (prioritize blocker/major; ignore nits unless needed):")
        for finding in findings[:max_findings]:
            if not isinstance(finding, dict):
                continue

            # review-v2 shape.
            title = _as_str(finding.get("title")).strip()
            body = _clip(_as_str(finding.get("body")), max_chars=900)
            priority = _priority_int(finding.get("priority"))
            location = _format_location(finding.get("code_location"))

            title_clean = _strip_priority_prefix(title) if title else ""
            line = "- "
            if priority is not None and 0 <= priority <= 3:
                line += f"[P{priority}] "
            if title_clean:
                line += title_clean
            elif title:
                line += title
            elif body:
                line += _clip(body, max_chars=240)
            else:
                line += "Finding"
            if location:
                line += f" ({location})"
            lines.append(line)
            if body:
                lines.append(f"  {body}")
        if len(findings) > max_findings:
            lines.append(f"...(truncated: {len(findings) - max_findings} more findings)")

    questions = obj.get("questions") or []
    if isinstance(questions, list) and questions:
        lines.append("Questions:")
        for q in questions:
            q_s = _clip(_as_str(q), max_chars=240)
            if q_s:
                lines.append(f"- {q_s}")

    uncertainty = obj.get("uncertainty") or []
    if isinstance(uncertainty, list) and uncertainty:
        lines.append("Uncertainty:")
        for u in uncertainty:
            u_s = _clip(_as_str(u), max_chars=240)
            if u_s:
                lines.append(f"- {u_s}")

    return lines


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract concise fix-focused text from code-review/pr-review JSON for implementation reruns."
    )
    parser.add_argument("review_json", help="Path to code-review.json or pr-review.json")
    parser.add_argument("--max-findings", type=int, default=20)
    parser.add_argument(
        "--max-chars",
        type=int,
        default=int(os.environ.get("MAX_REVIEW_FEEDBACK_CHARS", "12000")),
    )
    args = parser.parse_args()

    path = args.review_json
    with open(path, "r", encoding="utf-8") as fh:
        obj = json.load(fh)

    if _is_review_fragment(obj):
        lines = _format_review_fragment(obj, max_findings=max(1, args.max_findings))
    else:
        raise SystemExit(
            "Unrecognized review JSON shape; expected review-v2 output (code-review/review-parallel/pr-review)."
        )

    text = "\n".join(lines).strip() + "\n"
    if len(text) > args.max_chars:
        text = text[: args.max_chars].rstrip() + "\n...(truncated)\n"

    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
