# Backup test — 2026-02-24

## Commands
```bash
./tools/backup_run.sh
./tools/backup_restore_test.sh
```

## Output (sanitized)

### backup_run.sh (rc=0)
```text
[*] Stage: /home/socadmin/soc-cases/tmp/backup_stage_2026-02-24_162520
[*] Export volume: single-node_wazuh_api_configuration
Unable to find image 'ubuntu:24.04' locally
24.04: Pulling from library/ubuntu
01d7766a2e4a: Pulling fs layer
fd8cda969ed2: Download complete
01d7766a2e4a: Download complete
01d7766a2e4a: Pull complete
Digest: sha256:d1e2e92c075e5ca139d51a140fff46f84315c0fdce203eab2807c7e495eff4f9
Status: Downloaded newer image for ubuntu:24.04
[*] Export volume: single-node_wazuh_etc
[*] Export volume: single-node_wazuh_logs
[*] Export volume: single-node_wazuh_queue
tar: ./db/wdb: socket ignored
tar: ./tasks/task: socket ignored
tar: ./tasks/upgrade: socket ignored
tar: ./sockets/logtest: socket ignored
tar: ./sockets/wmodules: socket ignored
tar: ./sockets/auth: socket ignored
tar: ./sockets/control: socket ignored
tar: ./sockets/logcollector: socket ignored
tar: ./sockets/monitor: socket ignored
tar: ./sockets/download: socket ignored
tar: ./sockets/analysis: socket ignored
tar: ./sockets/updater-ondemand: socket ignored
tar: ./sockets/com: socket ignored
tar: ./sockets/syscheck: socket ignored
tar: ./sockets/remote: socket ignored
tar: ./sockets/queue: socket ignored
tar: ./alerts/ar: socket ignored
tar: ./alerts/cfgaq: socket ignored
tar: ./alerts/execq: socket ignored
tar: ./alerts/cfgarq: socket ignored
tar: ./router/deltas-syscollector: socket ignored
tar: ./router/vulnerability_feed_manager: socket ignored
tar: ./router/policy: socket ignored
tar: ./router/wdb-agent-events: socket ignored
tar: ./router/subscription.sock: socket ignored
tar: ./router/rsync-syscollector: socket ignored
[*] Export volume: single-node_wazuh_var_multigroups
[*] Export volume: single-node_wazuh_integrations
[*] Export volume: single-node_wazuh_active_response
[*] Export volume: single-node_wazuh_agentless
[*] Export volume: single-node_wazuh_wodles
[*] Export volume: single-node_wazuh-dashboard-config
[*] Export volume: single-node_wazuh-dashboard-custom
[*] Export volume: single-node_wazuh-indexer-data
[*] Export volume: single-node_filebeat_etc
[*] Export volume: single-node_filebeat_var
[*] Push to remote: 192.168.242.129
[OK] Backup completed: socbackup@192.168.242.129:/srv/soc-backups/latest
```

### backup_restore_test.sh (rc=0)
```text
[*] Pull remote latest into: /home/socadmin/soc-cases/tmp/backup_restore_test_2026-02-24_163454
[*] Validate presence of manifest
  OK: MANIFEST.txt present
[*] Validate expected directories
  OK: repo/, wazuh/, docker-volumes/ present
[*] Validate docker volume archives are readable (tar -tzf)
  OK: 14 volume archives readable
[*] Quick sanity checks
  OK: wazuh docker-compose.yml and config/ present
[OK] Restore test verified (no production changes).
```

## Conclusion
- restore verificado
