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
OVERALL_CORRECTNESS_ALLOWED = {"patch is correct", "patch is incorrect"}
RUN_ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")
SCOPE_ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")

REQUIRED_KEYS = {
    "facet",
    "facet_slug",
    "status",
    "findings",
    "questions",
    "uncertainty",
    "overall_correctness",
    "overall_explanation",
    "overall_confidence_score",
}
OPTIONAL_KEYS = {"schema_version", "scope_id"}
ALLOWED_KEYS = REQUIRED_KEYS | OPTIONAL_KEYS

TOP_LEVEL_KEY_ORDER = [
    "schema_version",
    "scope_id",
    "facet",
    "facet_slug",
    "status",
    "findings",
    "overall_correctness",
    "overall_explanation",
    "overall_confidence_score",
    "questions",
    "uncertainty",
]
FINDING_REQUIRED_KEYS = {
    "title",
    "body",
    "confidence_score",
    "priority",
    "code_location",
}
FINDING_KEY_ORDER = ["priority", "title", "body", "confidence_score", "code_location"]
CODE_LOCATION_REQUIRED_KEYS = {"repo_relative_path", "line_range"}
CODE_LOCATION_KEY_ORDER = ["repo_relative_path", "line_range"]
LINE_RANGE_REQUIRED_KEYS = {"start", "end"}
LINE_RANGE_KEY_ORDER = ["start", "end"]


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

    required = schema.get("required")
    if not isinstance(required, list) or set(required) != REQUIRED_KEYS:
        errors.append(f"schema.required must be {sorted(REQUIRED_KEYS)}")

    props = schema.get("properties")
    if not isinstance(props, dict):
        errors.append("schema.properties must be an object")
        return errors

    schema_version = props.get("schema_version")
    schema_version_enum = schema_version.get("enum") if isinstance(schema_version, dict) else None
    if not isinstance(schema_version_enum, list) or schema_version_enum != [2]:
        errors.append("schema.properties.schema_version.enum must be [2]")

    status = props.get("status")
    status_enum = status.get("enum") if isinstance(status, dict) else None
    if not isinstance(status_enum, list) or set(status_enum) != STATUS_ALLOWED:
        errors.append(f"schema.properties.status.enum must be {sorted(STATUS_ALLOWED)}")

    overall_correctness = props.get("overall_correctness")
    overall_correctness_enum = (
        overall_correctness.get("enum") if isinstance(overall_correctness, dict) else None
    )
    if (
        not isinstance(overall_correctness_enum, list)
        or set(overall_correctness_enum) != OVERALL_CORRECTNESS_ALLOWED
    ):
        errors.append(
            "schema.properties.overall_correctness.enum must be "
            f"{sorted(OVERALL_CORRECTNESS_ALLOWED)}"
        )

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

    f_required = items.get("required")
    if not isinstance(f_required, list) or set(f_required) != FINDING_REQUIRED_KEYS:
        errors.append(
            f"schema.properties.findings.items.required must be {sorted(FINDING_REQUIRED_KEYS)}"
        )

    item_props = items.get("properties")
    if not isinstance(item_props, dict):
        errors.append("schema.properties.findings.items.properties must be an object")
        return errors

    priority = item_props.get("priority")
    if not isinstance(priority, dict):
        errors.append("schema.properties.findings.items.properties.priority must be an object")
    else:
        if priority.get("type") != "integer":
            errors.append("schema.properties.findings.items.properties.priority.type must be integer")
        if priority.get("minimum") != 0 or priority.get("maximum") != 3:
            errors.append(
                "schema.properties.findings.items.properties.priority minimum/maximum must be 0/3"
            )

    return errors


def validate_fragment(obj: dict, expected_slug: str) -> List[str]:
    errors: List[str] = []

    if not isinstance(obj, dict):
        return ["root is not an object"]

    missing = REQUIRED_KEYS - set(obj.keys())
    if missing:
        errors.append(f"missing keys: {sorted(missing)}")

    extra = set(obj.keys()) - ALLOWED_KEYS
    if extra:
        errors.append(f"unexpected keys: {sorted(extra)}")

    schema_version = obj.get("schema_version")
    facet = obj.get("facet")
    facet_slug = obj.get("facet_slug")
    status = obj.get("status")
    findings = obj.get("findings")
    overall_correctness = obj.get("overall_correctness")
    overall_explanation = obj.get("overall_explanation")
    overall_confidence_score = obj.get("overall_confidence_score")
    questions = obj.get("questions")
    uncertainty = obj.get("uncertainty")

    if schema_version is not None and schema_version != 2:
        errors.append("schema_version must be 2 when present")

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
            f_missing = FINDING_REQUIRED_KEYS - set(item.keys())
            if f_missing:
                errors.append(f"findings[{idx}] missing keys: {sorted(f_missing)}")
            f_extra = set(item.keys()) - FINDING_REQUIRED_KEYS
            if f_extra:
                errors.append(f"findings[{idx}] unexpected keys: {sorted(f_extra)}")

            title = item.get("title")
            body = item.get("body")
            confidence_score = item.get("confidence_score")
            priority = item.get("priority")
            code_location = item.get("code_location")

            if not isinstance(title, str) or not title:
                errors.append(f"findings[{idx}].title must be a non-empty string")
            if isinstance(title, str) and len(title) > 120:
                errors.append(f"findings[{idx}].title must be <= 120 chars")
            if not isinstance(body, str) or not body:
                errors.append(f"findings[{idx}].body must be a non-empty string")
            if not isinstance(confidence_score, (int, float)) or not (0.0 <= float(confidence_score) <= 1.0):
                errors.append(f"findings[{idx}].confidence_score must be a number 0.0-1.0")
            if not isinstance(priority, int) or not (0 <= priority <= 3):
                errors.append(f"findings[{idx}].priority must be an int 0-3")

            if not isinstance(code_location, dict):
                errors.append(f"findings[{idx}].code_location must be an object")
            else:
                missing_loc = CODE_LOCATION_REQUIRED_KEYS - set(code_location.keys())
                if missing_loc:
                    errors.append(
                        f"findings[{idx}].code_location missing keys: {sorted(missing_loc)}"
                    )
                extra_loc = set(code_location.keys()) - CODE_LOCATION_REQUIRED_KEYS
                if extra_loc:
                    errors.append(
                        f"findings[{idx}].code_location unexpected keys: {sorted(extra_loc)}"
                    )
                repo_relative_path = code_location.get("repo_relative_path")
                if not isinstance(repo_relative_path, str) or not repo_relative_path:
                    errors.append(
                        f"findings[{idx}].code_location.repo_relative_path must be a non-empty string"
                    )
                if isinstance(repo_relative_path, str) and repo_relative_path.startswith("/"):
                    errors.append(
                        f"findings[{idx}].code_location.repo_relative_path must be repo-relative (not absolute)"
                    )

                line_range = code_location.get("line_range")
                if not isinstance(line_range, dict):
                    errors.append(f"findings[{idx}].code_location.line_range must be an object")
                else:
                    missing_lr = LINE_RANGE_REQUIRED_KEYS - set(line_range.keys())
                    if missing_lr:
                        errors.append(
                            f"findings[{idx}].code_location.line_range missing keys: {sorted(missing_lr)}"
                        )
                    extra_lr = set(line_range.keys()) - LINE_RANGE_REQUIRED_KEYS
                    if extra_lr:
                        errors.append(
                            f"findings[{idx}].code_location.line_range unexpected keys: {sorted(extra_lr)}"
                        )
                    start = line_range.get("start")
                    end = line_range.get("end")
                    if not isinstance(start, int) or start < 1:
                        errors.append(f"findings[{idx}].code_location.line_range.start must be int >= 1")
                    if not isinstance(end, int) or end < 1:
                        errors.append(f"findings[{idx}].code_location.line_range.end must be int >= 1")
                    if isinstance(start, int) and isinstance(end, int) and end < start:
                        errors.append(f"findings[{idx}].code_location.line_range.end must be >= start")

    if overall_correctness not in OVERALL_CORRECTNESS_ALLOWED:
        errors.append(
            f"overall_correctness must be one of {sorted(OVERALL_CORRECTNESS_ALLOWED)}"
        )
    if not isinstance(overall_explanation, str) or not overall_explanation:
        errors.append("overall_explanation must be a non-empty string")
    if not isinstance(overall_confidence_score, (int, float)) or not (0.0 <= float(overall_confidence_score) <= 1.0):
        errors.append("overall_confidence_score must be a number 0.0-1.0")

    if not isinstance(questions, list) or any(not isinstance(x, str) for x in questions):
        errors.append("questions must be an array of strings")
    if not isinstance(uncertainty, list) or any(not isinstance(x, str) for x in uncertainty):
        errors.append("uncertainty must be an array of strings")

    if status in {"Blocked", "Question"} and overall_correctness != "patch is incorrect":
        errors.append("Blocked/Question must have overall_correctness='patch is incorrect'")
    if status in {"Approved", "Approved with nits"} and overall_correctness != "patch is correct":
        errors.append("Approved/Approved with nits must have overall_correctness='patch is correct'")

    if status == "Approved":
        if isinstance(findings, list) and len(findings) != 0:
            errors.append("Approved must have findings=[]")
        if isinstance(questions, list) and len(questions) != 0:
            errors.append("Approved must have questions=[]")
    if status == "Approved with nits":
        if isinstance(findings, list):
            blocking = [f for f in findings if isinstance(f, dict) and f.get("priority") in (0, 1)]
            if blocking:
                errors.append("Approved with nits must not include priority 0/1 findings")
        if isinstance(questions, list) and len(questions) != 0:
            errors.append("Approved with nits must have questions=[]")
    if status == "Blocked":
        if isinstance(findings, list):
            blocking = [f for f in findings if isinstance(f, dict) and f.get("priority") in (0, 1)]
            if not blocking:
                errors.append("Blocked must include at least one priority 0/1 finding")
    if status == "Question":
        if isinstance(questions, list) and len(questions) == 0:
            errors.append("Question must include at least one question")

    return errors


def normalize_fragment(obj: dict) -> dict:
    ordered: dict = {}
    for key in TOP_LEVEL_KEY_ORDER:
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
                    if key != "code_location":
                        f_ordered[key] = item[key]
            code_location = item.get("code_location")
            if isinstance(code_location, dict):
                loc: dict = {}
                for k in CODE_LOCATION_KEY_ORDER:
                    if k in code_location and k != "line_range":
                        loc[k] = code_location[k]
                line_range = code_location.get("line_range")
                if isinstance(line_range, dict):
                    lr: dict = {}
                    for k in LINE_RANGE_KEY_ORDER:
                        if k in line_range:
                            lr[k] = line_range[k]
                    for k, v in line_range.items():
                        if k not in lr:
                            lr[k] = v
                    loc["line_range"] = lr
                for k, v in code_location.items():
                    if k not in loc:
                        loc[k] = v
                f_ordered["code_location"] = loc
            else:
                if "code_location" in item:
                    f_ordered["code_location"] = item["code_location"]

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
        default=".skilled-reviews/.reviews/schemas/review-v2.schema.json",
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

    scope_dir = os.path.join(".skilled-reviews/.reviews/reviewed_scopes", args.scope_id)
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
