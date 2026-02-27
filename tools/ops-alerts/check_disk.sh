#!/usr/bin/env bash
set -euo pipefail

# Disk usage check (MVP)
# - No secrets printed.
# - No CWD dependency.
# - Default: fail if / usage >= 90%.
#
# Config via env:
#   OPS_DISK_MOUNT (default "/")
#   OPS_DISK_WARN_PCT (default 85)
#   OPS_DISK_CRIT_PCT (default 90)

MOUNT="${OPS_DISK_MOUNT:-/}"
WARN="${OPS_DISK_WARN_PCT:-85}"
CRIT="${OPS_DISK_CRIT_PCT:-90}"

if ! command -v df >/dev/null 2>&1; then
  echo "FAIL: df not found"
  exit 2
fi

# Get usage percent for the mount (POSIX-ish).
# Example df output: Use% column like "73%"
USE_PCT="$(df -P "${MOUNT}" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"

if [[ -z "${USE_PCT}" || ! "${USE_PCT}" =~ ^[0-9]+$ ]]; then
  echo "FAIL: could not determine disk usage for ${MOUNT}"
  exit 2
fi

if (( USE_PCT >= CRIT )); then
  echo "FAIL: disk usage ${USE_PCT}% on ${MOUNT} (crit >= ${CRIT}%)"
  exit 1
fi

if (( USE_PCT >= WARN )); then
  echo "PASS: disk usage ${USE_PCT}% on ${MOUNT} (warn >= ${WARN}%, crit >= ${CRIT}%)"
  exit 0
fi

echo "PASS: disk usage ${USE_PCT}% on ${MOUNT} (ok < ${WARN}%)"
