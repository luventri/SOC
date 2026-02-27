# P1-PLAT-OPS-ALERTS-001 — Operational alerts (home SOC)

## Scope
Operational alerts for the home SOC platform to detect:
- ingest down (critical channels missing)
- disk high (platform host)
- agent offline

This runbook defines thresholds, actions, evidence generation and notification (GitHub Issues).

## Assumptions (MVP)
- Wazuh runs on `soc-core` (single-node Docker).
- Agents are discovered from the **Wazuh manager** (source of truth), not from “recent logs”.
- No secrets are stored in the repo. Any credentials live in `~/.secrets/mini-soc.env` with correct permissions.
- Scripts are runnable from any directory (no CWD dependency).
- Indexer queries require `WAZUH_INDEXER_USER/WAZUH_INDEXER_PASS` in the environment (loaded from `~/.secrets/mini-soc.env`). Credentials are never printed.

## Discovery (scalable)
**Source of truth:** Wazuh manager agent registry and status.

Implementation:
- `tools/ops-alerts/run_ops_alerts.sh` discovers agents via:
  - `docker exec <wazuh.manager> /var/ossec/bin/agent_control -l`
- The runner skips the server/local agent `ID: 000` and checks each discovered agent by its `Name` (maps to `data.win.system.computer` in Windows events).

## Alert definitions and thresholds (MVP)

### 1) Ingest down (critical channels)
**Definition:** For a given agent, no recent events in **critical channels** within the defined window.

**Critical channels (default):**
- Windows Security
- Microsoft-Windows-Sysmon/Operational

**Threshold (MVP, recommended defaults):**
- Default: fail if no critical-channel events in the last **60 minutes**.
- Stricter option: **15 minutes** (may be noisy in home SOC / idle endpoints).

**Action (short runbook):**
1. Confirm the agent is listed as Active in Wazuh manager (`agent_control -l`).
2. Confirm endpoint generates the expected channels (Security/Sysmon enabled and forwarding).
3. Check Wazuh manager/indexer health (containers up, indexer healthy).
4. If the agent is Active but critical channels are missing, treat as **telemetry gap** (coverage) and remediate collection.
5. If broader ingestion issues exist, collect Wazuh manager/indexer logs and restore service.

**Evidence / notification:**
- Evidence file under `artifacts/platform/ops-alerts/ops_alerts_YYYY-MM-DD.md` includes:
  - per-agent PASS/FAIL for ingest with window and latest timestamp/channel.
- On FAIL: create GitHub Issue with labels `platform,ops-alert,ingest`.

### 2) Agent offline
**Definition:** For a given agent, no events of any type (any channel) within the offline window.

**Threshold (MVP):**
- fail if no events for the agent in the last **60 minutes**.

**Action (short runbook):**
1. Check agent status in Wazuh manager (`agent_control -l`).
2. If disconnected: verify endpoint connectivity and agent service.
3. Check endpoint Wazuh agent logs and re-enroll if needed.
4. After remediation, re-run the runner and verify PASS.

**Evidence / notification:**
- Evidence file includes latest event time/channel or the absence of events.
- On FAIL: create GitHub Issue with labels `platform,ops-alert,agent`.

### 3) Disk high (platform host)
**Definition:** Platform disk usage is above safe thresholds on key mount(s).

**Threshold (MVP):**
- Warning: > **85%**
- Critical (fail): >= **90%**
- Default check evaluates `/` on `soc-core`.

**Action (short runbook):**
1. Identify filesystem/mount causing high usage (`df -P`).
2. Check Docker volumes, Wazuh indices, log rotation.
3. Apply safe cleanup (rotate logs, prune unused images) and/or increase disk.
4. Re-run checks and confirm usage back under threshold.

**Evidence / notification:**
- Evidence includes filesystem, usage %, thresholds and PASS/FAIL.
- On FAIL: create GitHub Issue with labels `platform,ops-alert,disk`.

## Evidence generation
- Runner writes a single daily summary artifact:
  - `artifacts/platform/ops-alerts/ops_alerts_YYYY-MM-DD.md`
- Artifacts must not contain secret values.

## Notification (MVP)
- On any FAIL, runner creates GitHub Issues automatically using `gh issue create` via `tools/ops-alerts/create_issue.sh`.
- Labels:
  - `platform`, `ops-alert`, plus one of: `ingest|disk|agent`
- Note: MVP may create duplicates if run repeatedly; dedupe can be added later.

## How to run
- Load env (indexer creds) and run:
  - `set -a && source ~/.secrets/mini-soc.env && set +a && tools/ops-alerts/run_ops_alerts.sh`
- Expected:
  - PASS run → artifact written + `OK: ops alerts PASS`
  - FAIL run → artifact written + issue URL(s) + `FAIL: ops alerts detected failures`

## Testing (required for closing P1)
- PASS evidence: a normal run producing `ops_alerts_YYYY-MM-DD.md` with `PASS`.
- FAIL evidence: simulated failure (example):
  - set `OPS_INGEST_WINDOW_MIN=0` to force ingest FAIL
  - confirm GitHub Issue created with labels `platform,ops-alert,ingest` (example issue: #8)

## References (official)
- Wazuh agent status / agent_control tool: Wazuh documentation.
- Wazuh API (optional alternative to agent_control): Wazuh documentation.
- OpenSearch query DSL (for indexer queries): OpenSearch documentation.

## Scheduling (recommended: systemd timer)
MVP scheduling uses a systemd timer for auditable execution and logs.

Repo files:
- `tools/ops-alerts/systemd/ops-alerts.service`
- `tools/ops-alerts/systemd/ops-alerts.timer`

Install (on soc-core):
1) Copy units:
- `sudo cp tools/ops-alerts/systemd/ops-alerts.service /etc/systemd/system/ops-alerts.service`
- `sudo cp tools/ops-alerts/systemd/ops-alerts.timer /etc/systemd/system/ops-alerts.timer`

2) Reload + enable:
- `sudo systemctl daemon-reload`
- `sudo systemctl enable --now ops-alerts.timer`

Operate / troubleshoot:
- Next/last runs: `systemctl list-timers --all | grep ops-alerts`
- Logs: `journalctl -u ops-alerts.service --since "24 hours ago" --no-pager`
