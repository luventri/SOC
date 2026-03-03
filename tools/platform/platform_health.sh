#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./tools/platform/platform_health.sh               # uses today's date
#   ./tools/platform/platform_health.sh 2026-02-24    # uses provided date (YYYY-MM-DD)

DATE="${1:-$(date +%F)}"
OUT="artifacts/platform/health/platform_health_${DATE}.md"

# Adjust these two if your paths/URL differ
COMPOSE="/home/socadmin/wazuh-docker/single-node/docker-compose.yml"
DASH_HOST="${OPS_DASH_HOSTNAME:-wazuh.dashboard}"
DASH_ADDR="${OPS_DASH_ADDR:-192.168.242.128}"
DASH_URL="${OPS_DASH_URL:-https://${DASH_HOST}:443}"
DASH_CA="${OPS_DASH_CA:-/home/socadmin/wazuh-docker/single-node/config/wazuh_indexer_ssl_certs/root-ca.pem}"

# Indexer
INDEXER_HOST="${OPS_INDEXER_HOSTNAME:-wazuh.indexer}"
INDEXER_ADDR="${OPS_INDEXER_ADDR:-127.0.0.1}"
INDEXER_URL="${OPS_INDEXER_URL:-https://${INDEXER_HOST}:9200}"
INDEXER_CA="${OPS_INDEXER_CA:-/home/socadmin/wazuh-docker/single-node/config/wazuh_indexer_ssl_certs/root-ca.pem}"
INDEXER_HEALTH_PATH="/_cluster/health"
INDEXER_CONTAINER_DEFAULT="single-node-wazuh.indexer-1"

mkdir -p artifacts

now_local="$(date '+%Y-%m-%d %H:%M %Z')"
host="$(hostname)"

# Optional: load secrets from ~/.secrets/mini-soc.env (if present)
# Expected vars (no secrets printed):
#   WAZUH_INDEXER_USER, WAZUH_INDEXER_PASS
#   (optional) INDEXER_CONTAINER
SECRETS_FILE="${HOME}/.secrets/mini-soc.env"
if [[ -f "${SECRETS_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "${SECRETS_FILE}"
  set +a
fi

INDEXER_CONTAINER="${INDEXER_CONTAINER:-${INDEXER_CONTAINER_DEFAULT}}"

if [[ ! -f "${INDEXER_CA}" ]]; then
  echo "FAIL: missing indexer CA file: ${INDEXER_CA}"
  exit 2
fi
if [[ ! -f "${DASH_CA}" ]]; then
  echo "FAIL: missing dashboard CA file: ${DASH_CA}"
  exit 2
fi

INDEXER_CURL_TLS=(--cacert "${INDEXER_CA}")
if [[ "${INDEXER_URL}" == "https://${INDEXER_HOST}:9200"* ]]; then
  INDEXER_CURL_TLS+=(--resolve "${INDEXER_HOST}:9200:${INDEXER_ADDR}")
fi

DASH_CURL_TLS=(--cacert "${DASH_CA}")
if [[ "${DASH_URL}" == "https://${DASH_HOST}:443"* ]]; then
  DASH_CURL_TLS+=(--resolve "${DASH_HOST}:443:${DASH_ADDR}")
fi

redact_stream() {
  # Conservative redaction if any sensitive keys appear in output accidentally
  sed -E 's/((password|pass|token|apikey|api_key|authorization)[^[:space:]]*)/\2=REDACTED/Ig'
}

write_block() {
  local title="$1"
  local cmd="$2"
  echo "## ${title}"
  echo "Command:"
  echo "- ${cmd}"
  echo
  echo "Output:"
  echo '```text'
  # Execute command safely
  bash -lc "${cmd}" 2>&1 | redact_stream
  echo '```'
  echo
}

{
  echo "# Platform Health — Wazuh single-node Docker (P0)"
  echo
  echo "- Date/time (local): ${now_local}"
  echo "- Host: ${host}"
  echo "- Compose file path: ${COMPOSE}"
  echo "- Dashboard URL used: ${DASH_URL}"
  echo

  # 1) docker compose ps (explicit compose path; no CWD dependency)
  write_block "1) docker compose ps" \
    "docker compose -f '${COMPOSE}' ps"

  # 2) docker ps (table)
  write_block "2) docker ps (table)" \
    "docker ps --format \"table {{.Names}}\\t{{.Status}}\\t{{.Ports}}\""

  # 3) Dashboard reachability (headers only)
  write_block "3) Dashboard reachability (headers only)" \
    "curl -sSI ${DASH_CURL_TLS[*]} \"${DASH_URL}\" | egrep -vi '^set-cookie:' | head -n 10"

  # 4) Indexer container status (Docker inspect)
  write_block "4) Indexer container status (docker inspect)" \
    "docker inspect --format='{{.Name}}  health={{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}  status={{.State.Status}}  started={{.State.StartedAt}}' '${INDEXER_CONTAINER}'"

  # 4.1) Indexer cluster health (auth) — no creds printed, only status JSON
  echo "## 4.1) Indexer cluster health (auth)"
  echo "Source:"
  echo "- ${INDEXER_URL}${INDEXER_HEALTH_PATH}"
  echo "Credentials:"
  echo "- Loaded from environment (WAZUH_INDEXER_USER/WAZUH_INDEXER_PASS); not printed"
  echo
  echo "Output (summary):"
  echo '```text'
  if [[ -n "${WAZUH_INDEXER_USER:-}" && -n "${WAZUH_INDEXER_PASS:-}" ]]; then
    TMP_OUT="$(mktemp)"
    HTTP_LINE="$(curl -sS "${INDEXER_CURL_TLS[@]}" -u "${WAZUH_INDEXER_USER}:${WAZUH_INDEXER_PASS}" -o "${TMP_OUT}" -w "HTTP=%{http_code} BYTES=%{size_download}\n" "${INDEXER_URL}${INDEXER_HEALTH_PATH}" || true)"
    echo "${HTTP_LINE}"
    if echo "${HTTP_LINE}" | grep -q "HTTP=200"; then
      python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); keys=[("status",j.get("status")),("cluster_name",j.get("cluster_name")),("number_of_nodes",j.get("number_of_nodes")),("active_shards_percent_as_number",j.get("active_shards_percent_as_number")),("unassigned_shards",j.get("unassigned_shards")),("timed_out",j.get("timed_out"))]; [print(f"{k}: {v}") for k,v in keys if v is not None]' "${TMP_OUT}"
    else
      echo "ERROR: non-200 response (see HTTP line above). Raw body (first 200 chars):"
      head -c 200 "${TMP_OUT}"; echo
    fi
    rm -f "${TMP_OUT}"
  else
    echo "SKIPPED: missing WAZUH_INDEXER_USER/WAZUH_INDEXER_PASS in environment or ${SECRETS_FILE}"
  fi
  echo '```'
  echo
  write_block "5) Listener exposure check (local)" \
    "ss -lntp | egrep '(:443|:9200|:55000)\\b' || true"

  echo "## Conclusion"
  echo "- If containers are Up and dashboard returns an HTTP response (commonly 302 to /app/login), the SIEM stack is operational."
  echo "- Indexer health is strongest when cluster health returns status=green/yellow and expected node count."
  echo "- If any service is down/unreachable, investigate with: docker compose -f ${COMPOSE} logs --tail 200 <service>"
  echo "- Security note: if listeners bind to 0.0.0.0/[::], restrict by firewall or bind addresses as needed for your environment."
} > "${OUT}"

echo "[OK] Wrote ${OUT}"
