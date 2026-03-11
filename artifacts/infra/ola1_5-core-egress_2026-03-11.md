# NET-BSL-001 Evidence — soc-core egress through pfSense (2026-03-11)

## Change metadata
- Capability: `NET-BSL-001`
- Host: `soc-core`
- Date (UTC): `2026-03-11`
- Operator: `SOC Engineer`
- Change type: network baseline hardening (routing/DNS path control)

## Pre-change state (observed)
- Two competing default routes:
  - `default via 192.168.242.2 dev ens33`
  - `default via 192.168.114.254 dev ens34`
- DNS defaults active on both links (`ens33` and `ens34`)
- Risk: nondeterministic egress path for SOC services.

## Applied change
- Updated `/etc/netplan/50-cloud-init.yaml` with:
  - `ens33.dhcp4-overrides.use-routes: false`
  - `ens33.dhcp4-overrides.use-dns: false`
  - `ens34.dhcp4-overrides.route-metric: 50`
- Applied with `sudo netplan try` and confirmed.
- Applied final state with `sudo netplan apply`.

## Post-change validation evidence

### 1) Routing
```text
default via 192.168.114.254 dev ens34 proto dhcp src 192.168.114.128 metric 50
192.168.114.0/24 dev ens34 proto kernel scope link src 192.168.114.128 metric 50
192.168.242.0/24 dev ens33 proto kernel scope link src 192.168.242.128 metric 100
```

### 2) Effective Internet path
```text
8.8.8.8 via 192.168.114.254 dev ens34 src 192.168.114.128
```

### 3) DNS/default-route scoping
```text
resolvectl dns:
  Link 2 (ens33):
  Link 3 (ens34): 192.168.114.254

resolvectl default-route:
  Link 2 (ens33): no
  Link 3 (ens34): yes
```

### 4) Connectivity
```text
ping -c 3 8.8.8.8      -> 0% packet loss (PASS)
ping -c 3 google.com   -> 0% packet loss (PASS)
```

### 5) SOC platform health after network change
```text
docker compose ps (single-node):
  single-node-wazuh.manager-1   Up
  single-node-wazuh.indexer-1   Up
  single-node-wazuh.dashboard-1 Up
```

## Conclusion
`NET-BSL-001` completed successfully. `soc-core` Internet egress is now deterministic through pfSense (`ens34`), while local network reachability remains intact and Wazuh services stay healthy.
