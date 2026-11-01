# Monitoring

Metrics only (Prometheus + Grafana). There is no log pipeline, so there are no per-path or per-status-code breakdowns here; see "What this does not cover" at the bottom.

| Source | Where it runs | Port | How it gets there |
|---|---|---|---|
| nginx (connections, requests) | `nginx-exporter` container, reads nginx's internal `stub_status` | 9113 | `docker/docker-compose.yaml` |
| Cloudflare tunnel (connections, requests, origin errors) | `cloudflared`'s own `/metrics` | 2000 | `docker/docker-compose.yaml` |
| Host (CPU, memory, disk, network) | `node_exporter` on the web VM | 9100 | `apt` (step 1 below) |

nginx's `stub_status` lives on an internal listener (port 8080). It is not published and the tunnel never forwards to it. CI fails if `/stub_status` ever answers on the public port 80.

Files in this folder:

- `prometheus-scrape.yml`: three jobs to add to your `prometheus.yml`
- `alerts.yml`: Prometheus alerting rules
- `grafana-dashboard.json`: dashboard to import into Grafana

## Setup

### 1. Install node_exporter on the web VM

```bash
sudo apt install -y prometheus-node-exporter
curl -s localhost:9100/metrics | head -3
```

### 2. Decide who may reach the metrics ports

Replace `<PROM_IP>` with the address Prometheus scrapes from.

**Port 9100 (`node_exporter`)** runs on the host, so the host firewall applies. With ufw:

```bash
sudo ufw allow from <PROM_IP> to any port 9100 proto tcp
```

**Ports 2000 and 9113** are published by Docker, and **Docker-published ports bypass the host's INPUT rules, and therefore ufw**: without extra rules they are open to the whole LAN. The place for rules about them is Docker's `DOCKER-USER` chain, which only exists once Docker is running and is not managed by ufw. `metrics-firewall.sh` adds the rules (idempotently) and `metrics-firewall.service` runs it after Docker starts, so they survive reboots and Docker restarts:

```bash
cd /home/webadmin/Website && git pull          # CI also does this on every deploy
sudo install -m 755 monitoring/metrics-firewall.sh /usr/local/sbin/metrics-firewall.sh
sudo install -m 644 monitoring/metrics-firewall.service /etc/systemd/system/metrics-firewall.service
echo 'PROM_IP=<PROM_IP>' | sudo tee /etc/default/metrics-firewall      # kept out of the repo
sudo systemctl daemon-reload
sudo systemctl enable --now metrics-firewall
```

Check it from any other device on the LAN: `curl -m 5 http://<WEB_VM_IP>:2000/metrics` should time out, while Prometheus's targets page still shows everything `UP`. The unit and script are copied with `install` (root-owned) on purpose, so that nothing running as root at boot is writable by the deploy user. After changing the script, copy it again and run `sudo systemctl restart metrics-firewall`.

The metrics are counters and gauges, nothing sensitive, so on a trusted home LAN skipping this is a defensible choice. It just leaves two ports readable by every device on the network.

### 3. Deploy the compose change

Merging to `main` deploys it. Afterwards, from the `docker/` folder on the VM:

```bash
docker compose ps
curl -s localhost:9113/metrics | grep -E "^nginx_up|^nginx_http_requests_total"
curl -s localhost:2000/metrics | grep -E "ha_connections|total_requests|request_errors"
```

`nginx_up` should be `1`, and `cloudflared_tunnel_ha_connections` should be at least `1`.

### 4. Prometheus

1. Add the jobs from `prometheus-scrape.yml` under `scrape_configs:` (replace `<WEB_VM_IP>`).
2. Add `alerts.yml` under `rule_files:`.
3. Reload (`curl -X POST http://localhost:9090/-/reload` if Prometheus runs with `--web.enable-lifecycle`, otherwise restart it).
4. Open **Status > Targets**: `web-nginx`, `web-cloudflared` and `web-node` should all be `UP`.

### 5. Grafana

**Dashboards > New > Import > Upload JSON file**, choose `grafana-dashboard.json`, pick your Prometheus data source. The queries expect the job names `web-nginx`, `web-cloudflared` and `web-node`; if you named yours differently, change them in the dashboard or in the scrape config.

### 6. Notifications

Prometheus alone only *evaluates* `alerts.yml`; it cannot send anything. Pick one:

- **Grafana alerting (least to run):** create a contact point (email, Telegram, ...), then **Alerting > Alert rules > New** for the most important ones, using the `expr` lines from `alerts.yml` as the query:
  - `cloudflared_tunnel_ha_connections{job="web-cloudflared"} == 0`
  - `nginx_up{job="web-nginx"} == 0 or up{job="web-nginx"} == 0`
  - `up{job="web-cloudflared"} == 0`
- **Alertmanager:** one extra container, configured with a receiver and pointed at from `prometheus.yml`.

## What this does not cover

- **The whole homelab being down.** Prometheus runs inside it, so a power or internet outage silences these alerts too. The external checks cover that: UptimeRobot on the public URL, and Cloudflare's tunnel health emails.
- **Status codes, top pages, countries, cache hit ratio.** nginx's `stub_status` and cloudflared's documented metrics don't have them, and there is no log pipeline. Cloudflare's own analytics (your domain > Analytics) already shows requests, countries, cache ratio and status codes without anything on your server. Check whether your cloudflared version also exposes `cloudflared_tunnel_response_by_code` (`curl -s localhost:2000/metrics | grep response_by_code`); if it does, it is easy to add a panel for it.
- **Per-container CPU and memory.** That needs cAdvisor, which this setup doesn't include. The host-level panels cover the VM as a whole.
