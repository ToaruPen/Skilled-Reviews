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

review_fragment_path="${schema_dir}/review-fragment.schema.json"
if [[ ! -f "$review_fragment_path" ]]; then
  content='{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "facet",
    "facet_slug",
    "status",
    "findings",
    "uncertainty",
    "questions"
  ],
  "properties": {
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
          "severity",
          "issue",
          "evidence",
          "impact",
          "fix_idea"
        ],
        "properties": {
          "severity": {
            "type": "string",
            "enum": [
              "blocker",
              "major",
              "minor",
              "nit"
            ]
          },
          "issue": {
            "type": "string"
          },
          "evidence": {
            "type": "string"
          },
          "impact": {
            "type": "string"
          },
          "fix_idea": {
            "type": "string"
          }
        }
      }
    },
    "uncertainty": {
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "questions": {
      "type": "array",
      "items": {
        "type": "string"
      }
    }
  }
}'
  write_schema "$review_fragment_path" <<<"$content"
fi

pr_review_path="${schema_dir}/pr-review.schema.json"
if [[ ! -f "$pr_review_path" ]]; then
  content='{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "scope_id",
    "status",
    "top_risks",
    "required_fixes",
    "optional_nits",
    "assumptions",
    "questions",
    "facet_coverage"
  ],
  "properties": {
    "scope_id": {
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
    "top_risks": {
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "required_fixes": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "issue",
          "evidence",
          "fix_idea"
        ],
        "properties": {
          "issue": {
            "type": "string"
          },
          "evidence": {
            "type": "string"
          },
          "fix_idea": {
            "type": "string"
          }
        }
      }
    },
    "optional_nits": {
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "assumptions": {
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "questions": {
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "facet_coverage": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "facet_slug",
          "status"
        ],
        "properties": {
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
          }
        }
      }
    }
  }
}'
  write_schema "$pr_review_path" <<<"$content"
fi
