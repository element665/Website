# Runbook

## After a reboot: does everything come back on its own?

Run this once after any change to the VM (or to prove it survives reboots). On the web VM:

```bash
sudo reboot
```

Wait a minute, log back in, then check each item:

```bash
# 1. All three containers are up and the healthchecks pass
cd /home/webadmin/Website/docker && docker compose ps
#    site and cloudflared should say (healthy); nginx-exporter should be Up

# 2. The running image is the last deployed commit
cat .env            # IMAGE_TAG=<sha>; compare with the latest successful deploy in GitHub Actions

# 3. The metrics firewall rules were re-applied after Docker started
systemctl status metrics-firewall --no-pager | head -5
sudo iptables -S DOCKER-USER | grep -E '2000|9113'

# 4. Host metrics are exposed
systemctl is-active prometheus-node-exporter
```

From other devices:

- The public site loads over HTTPS.
- A device that is not Prometheus times out on `curl -m 5 http://<WEB_VM_IP>:2000/metrics`.
- Prometheus **Status > Targets** shows `web-nginx`, `web-cloudflared` and `web-node` as `UP`.
- The Cloudflare tunnel shows as healthy, and you got a "tunnel restored" email.
- UptimeRobot shows the downtime, and the site as up again.

If something is missing, `docker compose logs --tail 50 <service>` and `journalctl -u <unit> -b` are the first places to look.

## Updating dependencies

Dependabot opens a pull request weekly for newer base images, Compose images and GitHub Actions. Each PR is built and smoke-tested by CI. Merging it to `main` deploys it, with automatic rollback if the health check fails. A pull request that fails CI is a version that doesn't work with this setup; close it or fix the cause.
