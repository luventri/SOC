#!/usr/bin/env bash
set -euo pipefail

# Runner (discovery via Wazuh Manager) for operational alerts
# - Discovers agents and status via agent_control inside wazuh.manager container.
# - Runs ingest+agent checks per agent name (data.win.system.computer).
# - Runs disk check once (local host).
# - Produces a single daily artifact and creates GitHub Issues on failures.
#
# Env:
#   OPS_MANAGER_CONTAINER (optional) default auto-detect
#   OPS_INGEST_WINDOW_MIN (default 60)
#   OPS_OFFLINE_WINDOW_MIN (default 60)
#   OPS_CHANNELS_CSV (default "Security,Microsoft-Windows-Sysmon/Operational")
#
# Credentials:
#   Uses WAZUH_INDEXER_USER/WAZUH_INDEXER_PASS from environment (loaded from ~/.secrets/mini-soc.env by caller/CI).

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ART_DIR="${REPO_ROOT}/artifacts/platform/ops-alerts"
DATE="$(date +%F)"
OUT="${ART_DIR}/ops_alerts_${DATE}.md"

mkdir -p "${ART_DIR}"

MANAGER_CTN="${OPS_MANAGER_CONTAINER:-}"
if [[ -z "${MANAGER_CTN}" ]]; then
  MANAGER_CTN="$(docker ps --format '{{.Names}}' | grep -E 'wazuh\.manager|wazuh-manager|wazuh_manager' | head -n 1 || true)"
fi

if [[ -z "${MANAGER_CTN}" ]]; then
  echo "FAIL: wazuh manager container not found"
  exit 2
fi

discover_agents() {
  # Output lines: "<id>\t<name>\t<status>"
  docker exec -i "${MANAGER_CTN}" /var/ossec/bin/agent_control -l 2>/dev/null \
  | awk -F',' '
    $0 ~ /^ *ID:/ {
      # Example: "ID: 001, Name: LAPTOP..., IP: any, Active"
      id=$1; name=$2; status=$4;
      gsub(/^ *ID: */,"",id);
      gsub(/^ *Name: */,"",name);
      gsub(/^ */,"",status);
      # skip server/local agent 000
      if (id!="000") printf "%s\t%s\t%s\n", id, name, status;
    }'
}

run_block() {
  local title="$1"; shift
  echo "### ${title}"
  echo "- Result:"
  echo '```text'
  set +e
  "$@"
  local rc=$?
  set -e
  echo '```'
  echo "- Status: $([[ $rc -eq 0 ]] && echo PASS || echo FAIL) (rc=${rc})"
  echo
  return $rc
}

FAIL_ITEMS=()

{
  echo "# Operational alerts (P1) — ${DATE}"
  echo
  echo "## Context"
  echo "- Host running checks: $(hostname)"
  echo "- Wazuh manager container: ${MANAGER_CTN}"
  echo "- Ingest window: ${OPS_INGEST_WINDOW_MIN:-60}m (critical channels)"
  echo "- Offline window: ${OPS_OFFLINE_WINDOW_MIN:-60}m (any channel)"
  echo

  echo "## Checks (platform host)"
  echo
  if run_block "Disk high" "${REPO_ROOT}/tools/ops-alerts/check_disk.sh"; then :; else FAIL_ITEMS+=("disk:platform"); fi

  echo "## Discovered agents (from agent_control)"
  echo
  AGENTS="$(discover_agents || true)"
  if [[ -z "${AGENTS}" ]]; then
    echo "FAIL: no agents discovered (unexpected)"
    FAIL_ITEMS+=("discovery:platform")
  else
    echo '```text'
    echo "${AGENTS}"
    echo '```'
  fi
  echo

  echo "## Checks (per agent)"
  echo
  if [[ -n "${AGENTS}" ]]; then
    while IFS=$'\t' read -r id name status; do
      [[ -z "${id}" || -z "${name}" ]] && continue
      echo "### Agent: ${id} / ${name} (${status})"
      echo
      # Always run ingest check per agent (critical channels)
      if OPS_HOSTNAME="${name}" run_block "Ingest down (critical channels)" "${REPO_ROOT}/tools/ops-alerts/check_ingest.sh"; then :; else FAIL_ITEMS+=("ingest:${name}"); fi
      # Agent offline: fail expected if agent is Disconnected OR no events
      if OPS_HOSTNAME="${name}" run_block "Agent offline" "${REPO_ROOT}/tools/ops-alerts/check_agent_offline.sh"; then :; else FAIL_ITEMS+=("agent:${name}"); fi
    done <<< "${AGENTS}"
  fi

  echo "## Conclusion"
  if [[ ${#FAIL_ITEMS[@]} -eq 0 ]]; then
    echo "**PASS** — all checks passed."
  else
    echo "**FAIL** — failures detected:"
    for x in "${FAIL_ITEMS[@]}"; do echo "- ${x}"; done
  fi
} > "${OUT}"

echo "OK: wrote ${OUT}"

# Notify on failures (one issue per failing item)
if [[ ${#FAIL_ITEMS[@]} -gt 0 ]]; then
  for item in "${FAIL_ITEMS[@]}"; do
    kind="${item%%:*}"
    target="${item#*:}"
    title="P1 OPS alert: ${kind} (${target}) ${DATE}"
    labels="platform,ops-alert,${kind}"
    "${REPO_ROOT}/tools/ops-alerts/create_issue.sh" "${title}" "${labels}" "${OUT}" || true
  done
  echo "FAIL: ops alerts detected failures"
  exit 1
fi

echo "OK: ops alerts PASS"
