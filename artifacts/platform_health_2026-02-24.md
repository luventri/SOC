# Platform Health — Wazuh single-node Docker (P0)

- Date/time (local): 2026-02-24 <HH:MM> (Europe/Madrid)
- Host: soc-core
- Compose file path: /home/socadmin/wazuh-docker/single-node/docker-compose.yml
- Dashboard URL used: https://192.168.242.128:443

## Evidence

### docker compose ps
Command:
- docker compose -f /home/socadmin/wazuh-docker/single-node/docker-compose.yml ps

Output:
```text
NAME                            IMAGE                         SERVICE           STATUS       PORTS
single-node-wazuh.dashboard-1   wazuh/wazuh-dashboard:4.9.2   wazuh.dashboard   Up 12 days   0.0.0.0:443->5601/tcp
single-node-wazuh.indexer-1     wazuh/wazuh-indexer:4.9.2     wazuh.indexer     Up 12 days   0.0.0.0:9200->9200/tcp
single-node-wazuh.manager-1     wazuh/wazuh-manager:4.9.2     wazuh.manager     Up 12 days   0.0.0.0:55000->55000/tcp
docker ps (table)

Command:

docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Output:

NAMES                           STATUS       PORTS
single-node-wazuh.dashboard-1   Up 12 days   443/tcp, 0.0.0.0:443->5601/tcp, [::]:443->5601/tcp
single-node-wazuh.manager-1     Up 12 days   0.0.0.0:1514-1515->1514-1515/tcp, [::]:1514-1515->1514-1515/tcp, 0.0.0.0:514->514/udp, [::]:514->514/udp, 0.0.0.0:55000->55000/tcp, [::]:55000->55000/tcp, 1516/tcp
single-node-wazuh.indexer-1     Up 12 days   0.0.0.0:9200->9200/tcp, [::]:9200->9200/tcp
Dashboard reachability

Command:

curl -kI https://192.168.242.128:443
 | head -n 5

Output:

HTTP/1.1 302 Found
location: /app/login?
osd-name: wazuh.dashboard
x-frame-options: sameorigin
cache-control: private, no-cache, no-store, must-revalidate
Indexer status (Docker inspect)

Command:

docker inspect --format='{{.Name}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}} status={{.State.Status}} started={{.State.StartedAt}}' single-node-wazuh.indexer-1

Output:

/single-node-wazuh.indexer-1  health=n/a  status=running  started=2026-02-12T10:27:30.376695727Z
Listener exposure check (local)

Command:

ss -lntp | egrep '(:443|:9200|:55000)\b'

Output:

LISTEN 0      4096         0.0.0.0:55000      0.0.0.0:*          
LISTEN 0      4096         0.0.0.0:443        0.0.0.0:*          
LISTEN 0      4096         0.0.0.0:9200       0.0.0.0:*          
LISTEN 0      4096            [::]:55000         [::]:*          
LISTEN 0      4096            [::]:443           [::]:*          
LISTEN 0      4096            [::]:9200          [::]:*          
Conclusion

Containers are running and stable (12 days uptime) and required ports are exposed.

Dashboard is reachable at https://192.168.242.128:443
 and redirects to login (HTTP 302), indicating the service is responding.

Indexer container is running; Docker healthcheck is not configured (health=n/a). Optional: add a healthcheck for stronger auditable status.

Security note: services are listening on 0.0.0.0 / [::] for 443, 9200, 55000. Exposure depends on firewall/NAT; restrict bindings or firewall rules if the intent is LAN/local-only.
