#!/usr/bin/env bash
set -euo pipefail

# Backup runner (SOC): creates a single "latest" backup on a remote backup server via rsync over SSH key.
# No CWD dependency: uses absolute paths and writes only to repo tmp/.

DATE="${1:-$(date +%F)}"
TS="$(date +%F_%H%M%S)"

REPO_ROOT="/home/socadmin/soc-cases"
WAZUH_COMPOSE="/home/socadmin/wazuh-docker/single-node/docker-compose.yml"
WAZUH_CONFIG_DIR="/home/socadmin/wazuh-docker/single-node/config"

# Docker volumes in use (from resolved compose)
VOLUMES=(
  "single-node_wazuh_api_configuration"
  "single-node_wazuh_etc"
  "single-node_wazuh_logs"
  "single-node_wazuh_queue"
  "single-node_wazuh_var_multigroups"
  "single-node_wazuh_integrations"
  "single-node_wazuh_active_response"
  "single-node_wazuh_agentless"
  "single-node_wazuh_wodles"
  "single-node_wazuh-dashboard-config"
  "single-node_wazuh-dashboard-custom"
  "single-node_wazuh-indexer-data"
  "single-node_filebeat_etc"
  "single-node_filebeat_var"
)

# Remote target
BACKUP_USER="socbackup"
BACKUP_HOST="192.168.242.129"
BACKUP_BASE="/srv/soc-backups"
SSH_KEY="${HOME}/.ssh/soc_backup_ed25519"

REMOTE_NEXT="${BACKUP_BASE}/latest.next"
REMOTE_LATEST="${BACKUP_BASE}/latest"

# Local staging (tmp) - not committed
STAGE="${REPO_ROOT}/tmp/backup_stage_${TS}"
mkdir -p "${STAGE}"

cleanup() { rm -rf "${STAGE}"; }
trap cleanup EXIT

echo "[*] Stage: ${STAGE}"

# 1) Repo content (exclude tmp/ and artifacts/ to avoid recursive backups)
mkdir -p "${STAGE}/repo"
rsync -a --delete \
  --exclude "/tmp/" \
  --exclude "/artifacts/" \
  "${REPO_ROOT}/" "${STAGE}/repo/"

# 2) Wazuh compose + config binds
mkdir -p "${STAGE}/wazuh"
cp -a "${WAZUH_COMPOSE}" "${STAGE}/wazuh/docker-compose.yml"
cp -a "${WAZUH_CONFIG_DIR}" "${STAGE}/wazuh/config"

# 3) Docker volumes -> tar.gz
mkdir -p "${STAGE}/docker-volumes"
for v in "${VOLUMES[@]}"; do
  echo "[*] Export volume: ${v}"
  docker run --rm -v "${v}:/v:ro" -v "${STAGE}/docker-volumes:/out" ubuntu:24.04 \
    bash -lc "cd /v && tar -czf /out/${v}.tar.gz ."
done

# 4) Manifest (no secrets)
cat > "${STAGE}/MANIFEST.txt" <<MAN
backup_date=${DATE}
backup_ts=${TS}
source_repo=${REPO_ROOT}
source_wazuh_compose=${WAZUH_COMPOSE}
source_wazuh_config=${WAZUH_CONFIG_DIR}
backup_mode=single_latest_atomic_swap
remote=${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_BASE}
MAN

# 5) Push to remote (atomic swap)
echo "[*] Push to remote: ${BACKUP_HOST}"
ssh -i "${SSH_KEY}" "${BACKUP_USER}@${BACKUP_HOST}" "mkdir -p '${REMOTE_NEXT}'"

rsync -a --delete -e "ssh -i ${SSH_KEY}" "${STAGE}/" "${BACKUP_USER}@${BACKUP_HOST}:${REMOTE_NEXT}/"

ssh -i "${SSH_KEY}" "${BACKUP_USER}@${BACKUP_HOST}" "rm -rf '${REMOTE_LATEST}' && mv '${REMOTE_NEXT}' '${REMOTE_LATEST}'"

echo "[OK] Backup completed: ${BACKUP_USER}@${BACKUP_HOST}:${REMOTE_LATEST}"
