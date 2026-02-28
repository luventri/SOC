#!/usr/bin/env bash
set -euo pipefail

# Create a GitHub Issue for Windows onboarding gate failures (no secrets).
# Avoids spamming: if an OPEN issue with the same title exists, it will not create a new one.

REPO="${GITHUB_REPO:-luventri/SOC}"

TITLE="${1:-}"
LABELS_BASE="windows,onboarding,coverage,telemetry"
BODY_FILE="${2:-}"

if [[ -z "${TITLE}" || -z "${BODY_FILE}" ]]; then
  echo "FAIL: usage: create_issue_on_fail.sh \"<title>\" <body_file>"
  exit 2
fi

if [[ ! -f "${BODY_FILE}" ]]; then
  echo "FAIL: body file not found: ${BODY_FILE}"
  exit 2
fi

# Add optional label if it exists (do not fail if missing)
if gh label list --repo "${REPO}" --limit 200 | awk '{print $1}' | grep -qx "data-quality"; then
  LABELS="${LABELS_BASE},data-quality"
else
  LABELS="${LABELS_BASE}"
fi

# Dedupe: if an OPEN issue with same title exists, do not create a new one
EXISTING_URL="$(gh issue list --repo "${REPO}" --state open --search "${TITLE} in:title" --json title,url --jq '.[] | select(.title=="'"${TITLE//\"/\\\"}"'") | .url' | head -n 1 || true)"
if [[ -n "${EXISTING_URL}" ]]; then
  echo "OK: issue already exists (open): ${EXISTING_URL}"
  exit 0
fi

URL="$(gh issue create --repo "${REPO}" --title "${TITLE}" --label "${LABELS}" --body-file "${BODY_FILE}")"
echo "OK: issue created ${URL}"
