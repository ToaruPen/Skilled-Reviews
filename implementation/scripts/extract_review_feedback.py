#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any


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


def _is_review_fragment(obj: Any) -> bool:
    return (
        isinstance(obj, dict)
        and isinstance(obj.get("facet_slug"), str)
        and isinstance(obj.get("status"), str)
        and isinstance(obj.get("findings"), list)
        and isinstance(obj.get("questions"), list)
    )


def _is_pr_review(obj: Any) -> bool:
    return (
        isinstance(obj, dict)
        and isinstance(obj.get("scope_id"), str)
        and isinstance(obj.get("status"), str)
        and isinstance(obj.get("required_fixes"), list)
        and isinstance(obj.get("questions"), list)
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
            severity = _as_str(finding.get("severity")).strip()
            issue = _clip(_as_str(finding.get("issue")), max_chars=240)
            if not issue:
                continue
            prefix = f"- [{severity}] " if severity else "- "
            lines.append(f"{prefix}{issue}")
            fix_idea = _clip(_as_str(finding.get("fix_idea")), max_chars=360)
            evidence = _clip(_as_str(finding.get("evidence")), max_chars=360)
            impact = _clip(_as_str(finding.get("impact")), max_chars=240)
            if fix_idea:
                lines.append(f"  fix_idea: {fix_idea}")
            if evidence:
                lines.append(f"  evidence: {evidence}")
            if impact:
                lines.append(f"  impact: {impact}")
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


def _format_pr_review(obj: dict[str, Any], *, max_fixes: int, max_nits: int) -> list[str]:
    lines: list[str] = []
    status = _as_str(obj.get("status")).strip()
    if status:
        lines.append(f"Status: {status}")

    required_fixes = obj.get("required_fixes") or []
    if isinstance(required_fixes, list) and required_fixes:
        lines.append("Required fixes:")
        for fix in required_fixes[:max_fixes]:
            if not isinstance(fix, dict):
                continue
            issue = _clip(_as_str(fix.get("issue")), max_chars=240)
            if not issue:
                continue
            lines.append(f"- {issue}")
            fix_idea = _clip(_as_str(fix.get("fix_idea")), max_chars=360)
            evidence = _clip(_as_str(fix.get("evidence")), max_chars=360)
            if fix_idea:
                lines.append(f"  fix_idea: {fix_idea}")
            if evidence:
                lines.append(f"  evidence: {evidence}")
        if len(required_fixes) > max_fixes:
            lines.append(f"...(truncated: {len(required_fixes) - max_fixes} more required fixes)")

    questions = obj.get("questions") or []
    if isinstance(questions, list) and questions:
        lines.append("Questions:")
        for q in questions:
            q_s = _clip(_as_str(q), max_chars=240)
            if q_s:
                lines.append(f"- {q_s}")

    optional_nits = obj.get("optional_nits") or []
    if isinstance(optional_nits, list) and optional_nits:
        lines.append("Optional nits (ignore unless trivial):")
        for nit in optional_nits[:max_nits]:
            nit_s = _clip(_as_str(nit), max_chars=240)
            if nit_s:
                lines.append(f"- {nit_s}")
        if len(optional_nits) > max_nits:
            lines.append(f"...(truncated: {len(optional_nits) - max_nits} more nits)")

    return lines


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract concise fix-focused text from code-review/pr-review JSON for implementation reruns."
    )
    parser.add_argument("review_json", help="Path to code-review.json or pr-review.json")
    parser.add_argument("--max-findings", type=int, default=20)
    parser.add_argument("--max-fixes", type=int, default=20)
    parser.add_argument("--max-nits", type=int, default=10)
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
    elif _is_pr_review(obj):
        lines = _format_pr_review(
            obj, max_fixes=max(1, args.max_fixes), max_nits=max(0, args.max_nits)
        )
    else:
        raise SystemExit(
            "Unrecognized review JSON shape; expected code-review fragment or pr-review aggregate."
        )

    text = "\n".join(lines).strip() + "\n"
    if len(text) > args.max_chars:
        text = text[: args.max_chars].rstrip() + "\n...(truncated)\n"

    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

