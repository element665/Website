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

`node_exporter` runs on the host, so the normal INPUT firewall applies. Allow Prometheus in the same way you allowed your other rules:

```bash
sudo iptables -I INPUT -p tcp -s <PROM_IP> --dport 9100 -j ACCEPT
```

Ports 2000 and 9113 are published by Docker. **Docker-published ports bypass the host's INPUT rules**, so an INPUT rule will neither allow nor block them. The place for rules about them is the `DOCKER-USER` chain:

```bash
sudo iptables -I DOCKER-USER ! -s <PROM_IP> -p tcp -m conntrack --ctorigdstport 2000 --ctdir ORIGINAL -j DROP
sudo iptables -I DOCKER-USER ! -s <PROM_IP> -p tcp -m conntrack --ctorigdstport 9113 --ctdir ORIGINAL -j DROP
```

Make them survive a reboot the same way you persisted your existing rules. The metrics contain nothing sensitive (counters and gauges), so on a trusted home LAN you can skip the `DOCKER-USER` rules, but then any device on the LAN can read them.

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

- **The whole homelab being down.** Prometheus runs inside it, so a power or internet outage silences the alerts too. Add one external check on the public URL (UptimeRobot, Better Stack, or Cloudflare health checks) that notifies you by email or push.
- **Status codes, top pages, countries, cache hit ratio.** nginx's `stub_status` and cloudflared's documented metrics don't have them, and there is no log pipeline. Cloudflare's own analytics (your domain > Analytics) already shows requests, countries, cache ratio and status codes without anything on your server. Check whether your cloudflared version also exposes `cloudflared_tunnel_response_by_code` (`curl -s localhost:2000/metrics | grep response_by_code`); if it does, it is easy to add a panel for it.
- **Per-container CPU and memory.** That needs cAdvisor, which this setup doesn't include. The host-level panels cover the VM as a whole.
