#!/bin/sh
# Restrict the Docker-published metrics ports (cloudflared 2000, nginx-exporter 9113) to the
# Prometheus host. Safe to run any number of times: each rule is added only if it is missing.
#
# Why this exists: ports published by Docker bypass the host's INPUT firewall (and therefore ufw),
# so they are open to the whole LAN unless rules are added to Docker's DOCKER-USER chain. That chain
# only exists once Docker is running and is not managed by ufw, so this runs from a systemd unit
# that starts after docker.service (monitoring/metrics-firewall.service).
#
# Configuration is read from /etc/default/metrics-firewall (kept out of the repo):
#   PROM_IP=192.0.2.10              required: the address Prometheus scrapes from
#   METRICS_PORTS="2000 9113"       optional: ports to restrict
set -eu

CONF="${METRICS_FIREWALL_CONF:-/etc/default/metrics-firewall}"
if [ -r "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF"
fi

if [ -z "${PROM_IP:-}" ]; then
  echo "metrics-firewall: PROM_IP is not set (put PROM_IP=<address> in $CONF)" >&2
  exit 1
fi
case "$PROM_IP" in
  *[!0-9.]* | *..* | .* | *.) echo "metrics-firewall: PROM_IP must be an IPv4 address, got '$PROM_IP'" >&2; exit 1 ;;
esac

PORTS="${METRICS_PORTS:-2000 9113}"
for port in $PORTS; do
  case "$port" in
    '' | *[!0-9]*) echo "metrics-firewall: invalid port '$port'" >&2; exit 1 ;;
  esac
done

# wait for dockerd to create the chain
waited=0
until iptables -n -L DOCKER-USER >/dev/null 2>&1; do
  waited=$((waited + 1))
  if [ "$waited" -gt "${WAIT_SECONDS:-30}" ]; then
    echo "metrics-firewall: chain DOCKER-USER does not exist (is Docker running?)" >&2
    exit 1
  fi
  sleep 1
done

for port in $PORTS; do
  # Match on the ORIGINAL destination port: by the time packets reach DOCKER-USER they have already
  # been DNATed to the container's own port, so a plain --dport would not see the published port.
  # shellcheck disable=SC2086
  set -- ! -s "$PROM_IP" -p tcp -m conntrack --ctorigdstport "$port" --ctdir ORIGINAL -j DROP
  if iptables -C DOCKER-USER "$@" 2>/dev/null; then
    echo "metrics-firewall: port $port already restricted to $PROM_IP"
  else
    iptables -I DOCKER-USER "$@"
    echo "metrics-firewall: port $port now restricted to $PROM_IP"
  fi
done
