#!/usr/bin/env bash
set -euo pipefail

REPO="${OPS_ALERTS_REPO:-luventri/SOC}"

if ! command -v gh >/dev/null 2>&1; then
  echo "FAIL: gh CLI not found"
  exit 2
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "FAIL: gh not authenticated (run: gh auth login)"
  exit 2
fi

TITLE="${1:-}"
LABELS_CSV="${2:-}"
BODY_FILE="${3:-}"

if [[ -z "${TITLE}" || -z "${LABELS_CSV}" || -z "${BODY_FILE}" ]]; then
  echo "FAIL: usage: create_issue.sh <title> <labels_csv> <body_file>"
  exit 2
fi

if [[ ! -f "${BODY_FILE}" ]]; then
  echo "FAIL: body file not found: ${BODY_FILE}"
  exit 2
fi

# Create issue. Do not echo body contents to stdout.
URL="$(gh issue create --repo "${REPO}" --title "${TITLE}" --label "${LABELS_CSV}" --body-file "${BODY_FILE}")"
echo "OK: issue created ${URL}"
