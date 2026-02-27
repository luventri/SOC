# Operational alerts (P1) — 2026-02-27

## Context
- Host running checks: soc-core
- Wazuh manager container: single-node-wazuh.manager-1
- Ingest window: 60m (critical channels)
- Offline window: 60m (any channel)

## Checks (platform host)

### Disk high
- Result:
```text
PASS: disk usage 36% on / (ok < 85%)
```
- Status: PASS (rc=0)

## Discovered agents (from agent_control)

```text
001	LAPTOP-RH48MVJ8	Active
```

## Checks (per agent)

### Agent: 001 / LAPTOP-RH48MVJ8 (Active)

### Ingest down (critical channels)
- Result:
```text
PASS: latest CRITICAL event for host=LAPTOP-RH48MVJ8 within 60m (channel=Security, ts=2026-02-27T09:14:57.214Z)
```
- Status: PASS (rc=0)

### Agent offline
- Result:
```text
PASS: host=LAPTOP-RH48MVJ8 has events within 60m (latest channel=Security, ts=2026-02-27T09:14:57.214Z)
```
- Status: PASS (rc=0)

## Conclusion
**PASS** — all checks passed.
