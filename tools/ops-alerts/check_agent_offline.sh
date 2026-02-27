#!/usr/bin/env bash
set -euo pipefail

# Agent offline check (MVP) - Wazuh archives
# Fails if NO events of any channel for the configured host within the window.
#
# Env config:
#   OPS_INDEXER_URL (default https://127.0.0.1:9200)
#   OPS_HOSTNAME (required) -> data.win.system.computer value
#   OPS_OFFLINE_WINDOW_MIN (default 60)
#
# Credentials:
#   Uses WAZUH_INDEXER_USER / WAZUH_INDEXER_PASS from environment (do not print).

INDEXER_URL="${OPS_INDEXER_URL:-https://127.0.0.1:9200}"
HOSTNAME="${OPS_HOSTNAME:-}"
WINDOW_MIN="${OPS_OFFLINE_WINDOW_MIN:-60}"

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

PAYLOAD="$(cat <<JSON
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

TMP="$(mktemp)"
HTTP="$(curl -sk -u "${WAZUH_INDEXER_USER}:${WAZUH_INDEXER_PASS}" -H 'Content-Type: application/json' \
  -o "${TMP}" -w "%{http_code}" \
  "${INDEXER_URL}/${INDEX}/_search" -d "${PAYLOAD}" || true)"

if [[ "${HTTP}" != "200" ]]; then
  echo "FAIL: indexer query failed (HTTP=${HTTP})"
  rm -f "${TMP}"
  exit 2
fi

python3 - "${TMP}" "${HOSTNAME}" "${WINDOW_MIN}" <<'PY'
import json,sys
path,host,win = sys.argv[1], sys.argv[2], sys.argv[3]
j=json.load(open(path))
hits=j.get("hits",{}).get("hits",[])
if not hits:
  print(f"FAIL: no events for host={host} in last {win}m (agent offline suspected)")
  sys.exit(1)
src=hits[0].get("_source",{})
ts=src.get("@timestamp","?")
dw=src.get("data",{}).get("win",{}).get("system",{}) if isinstance(src.get("data",{}),dict) else {}
ch=dw.get("channel","?") if isinstance(dw,dict) else "?"
print(f"PASS: host={host} has events within {win}m (latest channel={ch}, ts={ts})")
PY
RC=$?
rm -f "${TMP}"
exit "${RC}"
