#!/usr/bin/env bash
set -euo pipefail

# Restore test (SOC): pulls remote "latest" backup to a temp folder and validates content.
# Does NOT modify production containers/volumes.

TS="$(date +%F_%H%M%S)"
REPO_ROOT="/home/socadmin/soc-cases"

BACKUP_USER="socbackup"
BACKUP_HOST="192.168.242.129"
BACKUP_BASE="/srv/soc-backups"
SSH_KEY="${HOME}/.ssh/soc_backup_ed25519"

REMOTE_LATEST="${BACKUP_BASE}/latest"

TEST_DIR="${REPO_ROOT}/tmp/backup_restore_test_${TS}"
mkdir -p "${TEST_DIR}"

cleanup() { rm -rf "${TEST_DIR}"; }
trap cleanup EXIT

echo "[*] Pull remote latest into: ${TEST_DIR}"
rsync -a -e "ssh -i ${SSH_KEY}" "${BACKUP_USER}@${BACKUP_HOST}:${REMOTE_LATEST}/" "${TEST_DIR}/"

echo "[*] Validate presence of manifest"
test -f "${TEST_DIR}/MANIFEST.txt"
echo "  OK: MANIFEST.txt present"

echo "[*] Validate expected directories"
test -d "${TEST_DIR}/repo"
test -d "${TEST_DIR}/wazuh"
test -d "${TEST_DIR}/docker-volumes"
echo "  OK: repo/, wazuh/, docker-volumes/ present"

echo "[*] Validate docker volume archives are readable (tar -tzf)"
count=0
for f in "${TEST_DIR}/docker-volumes/"*.tar.gz; do
  test -f "$f"
  tar -tzf "$f" >/dev/null
  count=$((count+1))
done
echo "  OK: ${count} volume archives readable"

echo "[*] Quick sanity checks"
test -f "${TEST_DIR}/wazuh/docker-compose.yml"
test -d "${TEST_DIR}/wazuh/config"
echo "  OK: wazuh docker-compose.yml and config/ present"

echo "[OK] Restore test verified (no production changes)."
