#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
from typing import Dict, List, Optional, Tuple

DEFAULT_FACETS = [
    "correctness",
    "edge-cases",
    "security",
    "performance",
    "tests-observability",
    "design-consistency",
]

STATUS_ALLOWED = {"Approved", "Approved with nits", "Blocked", "Question"}
SEVERITY_ALLOWED = {"blocker", "major", "minor", "nit"}
RUN_ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")
SCOPE_ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")

FRAGMENT_KEY_ORDER = [
    "facet",
    "facet_slug",
    "status",
    "findings",
    "uncertainty",
    "questions",
]
FINDING_KEY_ORDER = [
    "severity",
    "issue",
    "evidence",
    "impact",
    "fix_idea",
]


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def load_run_id(scope_dir: str, run_id: Optional[str]) -> str:
    if run_id:
        return run_id
    current = os.path.join(scope_dir, ".current_run")
    if os.path.exists(current):
        with open(current, "r", encoding="utf-8") as fh:
            value = fh.read().strip()
        if value:
            return value
    eprint("run-id is required (or create .current_run)")
    sys.exit(1)


def validate_schema(schema: dict) -> List[str]:
    errors: List[str] = []

    if not isinstance(schema, dict):
        return ["schema root is not an object"]

    if schema.get("type") != "object":
        errors.append("schema.type must be 'object'")
    if schema.get("additionalProperties") is not False:
        errors.append("schema.additionalProperties must be false")

    expected_required = {
        "facet",
        "facet_slug",
        "status",
        "findings",
        "uncertainty",
        "questions",
    }
    required = schema.get("required")
    if not isinstance(required, list) or set(required) != expected_required:
        errors.append(f"schema.required must be {sorted(expected_required)}")

    props = schema.get("properties")
    if not isinstance(props, dict):
        errors.append("schema.properties must be an object")
        return errors

    status = props.get("status")
    status_enum = status.get("enum") if isinstance(status, dict) else None
    if not isinstance(status_enum, list) or set(status_enum) != STATUS_ALLOWED:
        errors.append(f"schema.properties.status.enum must be {sorted(STATUS_ALLOWED)}")

    findings = props.get("findings")
    if not isinstance(findings, dict) or findings.get("type") != "array":
        errors.append("schema.properties.findings must be an array")
        return errors

    items = findings.get("items")
    if not isinstance(items, dict) or items.get("type") != "object":
        errors.append("schema.properties.findings.items must be an object schema")
        return errors

    if items.get("additionalProperties") is not False:
        errors.append("schema.properties.findings.items.additionalProperties must be false")

    expected_f_required = {"severity", "issue", "evidence", "impact", "fix_idea"}
    f_required = items.get("required")
    if not isinstance(f_required, list) or set(f_required) != expected_f_required:
        errors.append(f"schema.properties.findings.items.required must be {sorted(expected_f_required)}")

    item_props = items.get("properties")
    if not isinstance(item_props, dict):
        errors.append("schema.properties.findings.items.properties must be an object")
        return errors

    severity = item_props.get("severity")
    severity_enum = severity.get("enum") if isinstance(severity, dict) else None
    if not isinstance(severity_enum, list) or set(severity_enum) != SEVERITY_ALLOWED:
        errors.append(
            f"schema.properties.findings.items.properties.severity.enum must be {sorted(SEVERITY_ALLOWED)}"
        )

    return errors


def validate_fragment(obj: dict, expected_slug: str) -> List[str]:
    errors: List[str] = []
    required = {"facet", "facet_slug", "status", "findings", "uncertainty", "questions"}

    if not isinstance(obj, dict):
        return ["root is not an object"]

    missing = required - set(obj.keys())
    if missing:
        errors.append(f"missing keys: {sorted(missing)}")

    extra = set(obj.keys()) - required
    if extra:
        errors.append(f"unexpected keys: {sorted(extra)}")

    facet = obj.get("facet")
    facet_slug = obj.get("facet_slug")
    status = obj.get("status")
    findings = obj.get("findings")
    uncertainty = obj.get("uncertainty")
    questions = obj.get("questions")

    if not isinstance(facet, str) or not facet:
        errors.append("facet must be a non-empty string")
    if not isinstance(facet_slug, str) or not facet_slug:
        errors.append("facet_slug must be a non-empty string")
    if isinstance(facet_slug, str) and facet_slug != expected_slug:
        errors.append(f"facet_slug mismatch: expected {expected_slug}, got {facet_slug}")
    if status not in STATUS_ALLOWED:
        errors.append(f"status must be one of {sorted(STATUS_ALLOWED)}")

    if not isinstance(findings, list):
        errors.append("findings must be an array")
    else:
        for idx, item in enumerate(findings):
            if not isinstance(item, dict):
                errors.append(f"findings[{idx}] is not an object")
                continue
            f_required = {"severity", "issue", "evidence", "impact", "fix_idea"}
            f_missing = f_required - set(item.keys())
            if f_missing:
                errors.append(f"findings[{idx}] missing keys: {sorted(f_missing)}")
            f_extra = set(item.keys()) - f_required
            if f_extra:
                errors.append(f"findings[{idx}] unexpected keys: {sorted(f_extra)}")
            severity = item.get("severity")
            if severity not in SEVERITY_ALLOWED:
                errors.append(
                    f"findings[{idx}].severity must be one of {sorted(SEVERITY_ALLOWED)}"
                )
            for key in ("issue", "evidence", "impact", "fix_idea"):
                if key in item and not isinstance(item[key], str):
                    errors.append(f"findings[{idx}].{key} must be a string")

    if not isinstance(uncertainty, list) or any(not isinstance(x, str) for x in uncertainty):
        errors.append("uncertainty must be an array of strings")
    if not isinstance(questions, list) or any(not isinstance(x, str) for x in questions):
        errors.append("questions must be an array of strings")

    return errors


def normalize_fragment(obj: dict) -> dict:
    ordered: dict = {}
    for key in FRAGMENT_KEY_ORDER:
        if key in obj:
            ordered[key] = obj[key]

    findings = ordered.get("findings")
    if isinstance(findings, list):
        normalized_findings = []
        for item in findings:
            if not isinstance(item, dict):
                normalized_findings.append(item)
                continue
            f_ordered: dict = {}
            for key in FINDING_KEY_ORDER:
                if key in item:
                    f_ordered[key] = item[key]
            for key, value in item.items():
                if key not in f_ordered:
                    f_ordered[key] = value
            normalized_findings.append(f_ordered)
        ordered["findings"] = normalized_findings

    for key, value in obj.items():
        if key not in ordered:
            ordered[key] = value

    return ordered


def write_pretty_json(path: str, data: dict) -> None:
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(tmp, path)


def validate_extra(extra_path: str, expected_slug: str) -> List[str]:
    try:
        with open(extra_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as exc:
        return [f"invalid JSON: {exc}"]
    return validate_fragment(data, expected_slug)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate review-parallel fragment JSONs for a run."
    )
    parser.add_argument("scope_id", help="Scope identifier (ticket/PR/etc.)")
    parser.add_argument("run_id", nargs="?", help="Run identifier (default: .current_run)")
    parser.add_argument(
        "--facets",
        default=",".join(DEFAULT_FACETS),
        help="Comma-separated facet slugs",
    )
    parser.add_argument(
        "--schema",
        default="docs/.reviews/schemas/review-fragment.schema.json",
        help="Schema path (checked for consistency with the validator)",
    )
    parser.add_argument(
        "--extra-file",
        default="",
        help="Optional extra fragment JSON to validate",
    )
    parser.add_argument(
        "--extra-slug",
        default="",
        help="Expected facet_slug for the extra fragment",
    )
    parser.add_argument(
        "--format",
        action="store_true",
        help="Rewrite validated JSON files with pretty formatting.",
    )
    args = parser.parse_args()

    if not SCOPE_ID_RE.match(args.scope_id):
        eprint(f"invalid scope-id: {args.scope_id}")
        return 1
    if args.scope_id in {".", ".."}:
        eprint(f"invalid scope-id: {args.scope_id} (not '.' or '..')")
        return 1

    schema_path = args.schema
    if not os.path.isfile(schema_path):
        eprint(f"schema not found: {schema_path}")
        return 1
    try:
        with open(schema_path, "r", encoding="utf-8") as fh:
            schema_doc = json.load(fh)
    except Exception as exc:
        eprint(f"schema invalid JSON: {exc}")
        return 1
    schema_errors = validate_schema(schema_doc)
    if schema_errors:
        eprint("schema mismatch (update schema generator and/or validator):")
        for err in schema_errors:
            eprint(f"  - {err}")
        return 1

    facets = [f.strip() for f in args.facets.split(",") if f.strip()]
    extra_file = args.extra_file.strip()
    extra_slug = args.extra_slug.strip()
    if not facets and not extra_file:
        eprint("no facets provided (set --facets or --extra-file)")
        return 1

    scope_dir = os.path.join("docs/.reviews/reviewed_scopes", args.scope_id)
    run_id = load_run_id(scope_dir, args.run_id)
    if not RUN_ID_RE.match(run_id):
        eprint(f"invalid run-id: {run_id}")
        return 1
    if run_id in {".", ".."}:
        eprint(f"invalid run-id: {run_id} (not '.' or '..')")
        return 1

    run_dir = os.path.join(scope_dir, run_id)
    if not os.path.isdir(run_dir):
        eprint(f"run directory not found: {run_dir}")
        return 1

    missing = []
    invalid: List[Tuple[str, List[str]]] = []
    facet_data: Dict[str, dict] = {}
    for slug in facets:
        path = os.path.join(run_dir, f"{slug}.json")
        if not os.path.isfile(path):
            missing.append(slug)
            continue
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception as exc:
            invalid.append((slug, [f"invalid JSON: {exc}"]))
            continue
        errors = validate_fragment(data, slug)
        if errors:
            invalid.append((slug, errors))
            continue
        facet_data[slug] = data

    if missing:
        eprint(f"missing facets: {missing}")
    if invalid:
        for slug, errors in invalid:
            eprint(f"invalid facet '{slug}':")
            for err in errors:
                eprint(f"  - {err}")

    if missing or invalid:
        return 1

    extra_data: Optional[dict] = None
    if extra_file:
        if not extra_slug:
            eprint("extra-slug is required when --extra-file is set")
            return 1
        if not os.path.isfile(extra_file):
            eprint(f"extra file not found: {extra_file}")
            return 1
        try:
            with open(extra_file, "r", encoding="utf-8") as fh:
                extra_data = json.load(fh)
        except Exception as exc:
            eprint(f"invalid extra fragment '{extra_slug}':")
            eprint(f"  - invalid JSON: {exc}")
            return 1

        extra_errors = validate_fragment(extra_data, extra_slug)
        if extra_errors:
            eprint(f"invalid extra fragment '{extra_slug}':")
            for err in extra_errors:
                eprint(f"  - {err}")
            return 1

    if args.format:
        for slug, data in facet_data.items():
            path = os.path.join(run_dir, f"{slug}.json")
            write_pretty_json(path, normalize_fragment(data))
        if extra_file and extra_data is not None:
            write_pretty_json(extra_file, normalize_fragment(extra_data))

    parts = []
    if facets:
        parts.append(f"{len(facets)} fragments valid")
    if extra_file:
        parts.append(f"extra fragment '{extra_slug}' valid")
    print(f"OK: {', '.join(parts)} in run-id {run_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
