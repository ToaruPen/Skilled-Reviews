#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  echo "Not in a git repository; cannot locate repo root." >&2
  exit 1
fi

schema_dir="${repo_root}/.skilled-reviews/.reviews/schemas"
mkdir -p "$schema_dir"

write_schema() {
  local path="$1"
  if [[ -f "$path" ]]; then
    return 0
  fi

  local tmp="${path}.tmp.$$"
  cat > "$tmp"
  mv "$tmp" "$path"
  echo "Generated schema: $path" >&2
}

review_v2_path="${schema_dir}/review-v2.schema.json"
if [[ ! -f "$review_v2_path" ]]; then
  content='{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "facet",
    "facet_slug",
    "status",
    "findings",
    "questions",
    "uncertainty",
    "overall_correctness",
    "overall_explanation",
    "overall_confidence_score"
  ],
  "properties": {
    "schema_version": {
      "type": "integer",
      "enum": [
        2
      ]
    },
    "scope_id": {
      "type": "string",
      "minLength": 1
    },
    "facet": {
      "type": "string",
      "minLength": 1
    },
    "facet_slug": {
      "type": "string",
      "minLength": 1
    },
    "status": {
      "type": "string",
      "enum": [
        "Approved",
        "Approved with nits",
        "Blocked",
        "Question"
      ]
    },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "title",
          "body",
          "confidence_score",
          "priority",
          "code_location"
        ],
        "properties": {
          "title": {
            "type": "string",
            "minLength": 1,
            "maxLength": 120
          },
          "body": {
            "type": "string",
            "minLength": 1
          },
          "confidence_score": {
            "type": "number",
            "minimum": 0,
            "maximum": 1
          },
          "priority": {
            "type": "integer",
            "minimum": 0,
            "maximum": 3
          },
          "code_location": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "repo_relative_path",
              "line_range"
            ],
            "properties": {
              "repo_relative_path": {
                "type": "string",
                "minLength": 1
              },
              "line_range": {
                "type": "object",
                "additionalProperties": false,
                "required": [
                  "start",
                  "end"
                ],
                "properties": {
                  "start": {
                    "type": "integer",
                    "minimum": 1
                  },
                  "end": {
                    "type": "integer",
                    "minimum": 1
                  }
                }
              }
            }
          }
        }
      }
    },
    "questions": {
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "uncertainty": {
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "overall_correctness": {
      "type": "string",
      "enum": [
        "patch is correct",
        "patch is incorrect"
      ]
    },
    "overall_explanation": {
      "type": "string",
      "minLength": 1
    },
    "overall_confidence_score": {
      "type": "number",
      "minimum": 0,
      "maximum": 1
    }
  }
}'
  write_schema "$review_v2_path" <<<"$content"
fi
