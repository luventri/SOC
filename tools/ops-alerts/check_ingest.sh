#!/usr/bin/env bash
set -euo pipefail

# Ingest check (MVP) - Wazuh archives
# Fails if no recent events for the configured host on critical channels.
# If it fails, prints also the latest ANY-channel event for the host (diagnostic).
#
# Env config:
#   OPS_INDEXER_URL (default https://127.0.0.1:9200)
#   OPS_HOSTNAME (required) -> data.win.system.computer value
#   OPS_INGEST_WINDOW_MIN (default 60)
#   OPS_CHANNELS_CSV (default "Security,Microsoft-Windows-Sysmon/Operational")
#
# Credentials:
#   Uses WAZUH_INDEXER_USER / WAZUH_INDEXER_PASS from environment (do not print).

INDEXER_URL="${OPS_INDEXER_URL:-https://127.0.0.1:9200}"
HOSTNAME="${OPS_HOSTNAME:-}"
WINDOW_MIN="${OPS_INGEST_WINDOW_MIN:-60}"
CHANNELS_CSV="${OPS_CHANNELS_CSV:-Security,Microsoft-Windows-Sysmon/Operational}"

if [[ -z "${HOSTNAME}" ]]; then
  echo "FAIL: OPS_HOSTNAME not set (expected data.win.system.computer value)"
  exit 2
fi

if [[ -z "${WAZUH_INDEXER_USER:-}" || -z "${WAZUH_INDEXER_PASS:-}" ]]; then
  echo "FAIL: missing WAZUH_INDEXER_USER/WAZUH_INDEXER_PASS in environment"
  exit 2
fi

INDEX="wazuh-archives-4.x-$(date +%Y.%m.%d)"

HTTP_IDX="$(curl -sk -u "${WAZUH_INDEXER_USER}:${WAZUH_INDEXER_PASS}" -o /dev/null -w "%{http_code}" "${INDEXER_URL}/${INDEX}")"
if [[ "${HTTP_IDX}" != "200" ]]; then
  echo "FAIL: index not available today: ${INDEX} (HTTP=${HTTP_IDX})"
  exit 2
fi

IFS=',' read -r -a CH_ARR <<< "${CHANNELS_CSV}"
CH_JSON="["
for c in "${CH_ARR[@]}"; do
  c_trim="$(echo "$c" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "${c_trim}" ]] && continue
  CH_JSON="${CH_JSON}\"${c_trim}\","
done
CH_JSON="${CH_JSON%,}]"

query_latest() {
  local mode="$1"   # critical|any
  local payload
  if [[ "${mode}" == "critical" ]]; then
    payload="$(cat <<JSON
{
  "size": 1,
  "query": {
    "bool": {
      "filter": [
        { "range": { "@timestamp": { "gte": "now-${WINDOW_MIN}m" } } },
        { "term": { "data.win.system.computer": "${HOSTNAME}" } },
        { "terms": { "data.win.system.channel": ${CH_JSON} } }
      ]
    }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }],
  "_source": ["@timestamp","data.win.system.computer","data.win.system.channel"]
}
JSON
)"
  else
    payload="$(cat <<JSON
{
  "size": 1,
  "query": {
    "bool": {
      "filter": [
        { "range": { "@timestamp": { "gte": "now-${WINDOW_MIN}m" } } },
        { "term": { "data.win.system.computer": "${HOSTNAME}" } }
      ]
    }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }],
  "_source": ["@timestamp","data.win.system.computer","data.win.system.channel"]
}
JSON
)"
  fi

  local tmp http
  tmp="$(mktemp)"
  http="$(curl -sk -u "${WAZUH_INDEXER_USER}:${WAZUH_INDEXER_PASS}" -H 'Content-Type: application/json' \
    -o "${tmp}" -w "%{http_code}" \
    "${INDEXER_URL}/${INDEX}/_search" -d "${payload}" || true)"
  echo "${http}:${tmp}"
}

crit="$(query_latest critical)"
crit_http="${crit%%:*}"
crit_tmp="${crit#*:}"

if [[ "${crit_http}" != "200" ]]; then
  echo "FAIL: indexer query failed (HTTP=${crit_http})"
  echo "INFO: ${INDEX} host=${HOSTNAME} window=${WINDOW_MIN}m channels=${CHANNELS_CSV}"
  rm -f "${crit_tmp}"
  exit 2
fi

python3 - "${crit_tmp}" "${HOSTNAME}" "${WINDOW_MIN}" "${CHANNELS_CSV}" <<'PY'
import json,sys
path,host,win,channels = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
j=json.load(open(path))
hits=j.get("hits",{}).get("hits",[])
if hits:
  src=hits[0].get("_source",{})
  ts=src.get("@timestamp","?")
  dw=src.get("data",{}).get("win",{}).get("system",{}) if isinstance(src.get("data",{}),dict) else {}
  ch=dw.get("channel","?") if isinstance(dw,dict) else "?"
  print(f"PASS: latest CRITICAL event for host={host} within {win}m (channel={ch}, ts={ts})")
  sys.exit(0)
print(f"FAIL: no CRITICAL events for host={host} in last {win}m (channels={channels})")
sys.exit(1)
PY
rc=$?
rm -f "${crit_tmp}"

if [[ "${rc}" -eq 0 ]]; then
  exit 0
fi

# Diagnostic: show latest ANY event for the host in the same window
any="$(query_latest any)"
any_http="${any%%:*}"
any_tmp="${any#*:}"
if [[ "${any_http}" == "200" ]]; then
  python3 - "${any_tmp}" "${HOSTNAME}" "${WINDOW_MIN}" <<'PY'
import json,sys
path,host,win = sys.argv[1], sys.argv[2], sys.argv[3]
j=json.load(open(path))
hits=j.get("hits",{}).get("hits",[])
if not hits:
  print(f"INFO: no ANY-channel events for host={host} in last {win}m")
  sys.exit(0)
src=hits[0].get("_source",{})
ts=src.get("@timestamp","?")
dw=src.get("data",{}).get("win",{}).get("system",{}) if isinstance(src.get("data",{}),dict) else {}
ch=dw.get("channel","?") if isinstance(dw,dict) else "?"
print(f"INFO: latest ANY event for host={host} within {win}m (channel={ch}, ts={ts})")
PY
fi
rm -f "${any_tmp}"

exit 1
