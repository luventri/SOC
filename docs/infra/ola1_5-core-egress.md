# NET-BSL-001 — soc-core egress only through pfSense

## Objective
Force `soc-core` Internet egress through pfSense only, preserving internal reachability and SOC platform availability.

## Scope
- Host: `soc-core`
- Configuration target: `/etc/netplan/50-cloud-init.yaml`
- Network intent:
  - Keep `ens33` on `192.168.242.0/24` for local/internal reachability only
  - Use `ens34` (`192.168.114.0/24`) as single default route and DNS path via pfSense (`192.168.114.254`)

## Applied configuration
```yaml
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: true
      dhcp4-overrides:
        use-routes: false
        use-dns: false
    ens34:
      dhcp4: true
      dhcp4-overrides:
        route-metric: 50
```

## Execution procedure
```bash
sudo cp /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak.$(date +%F_%H%M%S)
sudo tee /etc/netplan/50-cloud-init.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: true
      dhcp4-overrides:
        use-routes: false
        use-dns: false
    ens34:
      dhcp4: true
      dhcp4-overrides:
        route-metric: 50
EOF
sudo netplan try
sudo netplan apply
```

## Validation commands
```bash
ip r
ip route get 8.8.8.8
resolvectl dns
resolvectl default-route
ping -c 3 8.8.8.8
ping -c 3 google.com
cd ~/wazuh-docker/single-node && docker compose ps
```

## Acceptance result
- Default route only via `ens34 -> 192.168.114.254`: PASS
- `ip route get 8.8.8.8` through pfSense path: PASS
- DNS default only on `ens34`: PASS
- Internet connectivity (`8.8.8.8`, `google.com`): PASS
- Wazuh stack (`manager/indexer/dashboard`) remains `Up`: PASS

## Rollback
```bash
sudo cp /etc/netplan/50-cloud-init.yaml.bak.<timestamp> /etc/netplan/50-cloud-init.yaml
sudo netplan apply
```

## Next step
Proceed with `LAB-BSL-002` (lab source scope hygiene) before Wave 2.
