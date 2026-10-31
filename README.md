<div align="center">

```
██████╗ ███████╗██╗   ██╗ ██████╗ ██████╗ ███████╗
██╔══██╗██╔════╝██║   ██║██╔═══██╗██╔══██╗██╔════╝
██║  ██║█████╗  ██║   ██║██║   ██║██████╔╝███████╗
██║  ██║██╔══╝  ╚██╗ ██╔╝██║   ██║██╔═══╝ ╚════██║
██████╔╝███████╗ ╚████╔╝ ╚██████╔╝██║     ███████║
╚═════╝ ╚══════╝  ╚═══╝   ╚═════╝ ╚═╝     ╚══════╝
```

# Portfolio Infrastructure

### A static site that proves I can think in systems — not just tools.

![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)
![Docker Compose](https://img.shields.io/badge/Docker_Compose-2496ED?style=flat-square&logo=docker&logoColor=white)
![NGINX](https://img.shields.io/badge/NGINX-009639?style=flat-square&logo=nginx&logoColor=white)
![Cloudflare](https://img.shields.io/badge/Cloudflare_Tunnel-F38020?style=flat-square&logo=cloudflare&logoColor=white)
![Tailscale](https://img.shields.io/badge/Tailscale-242424?style=flat-square&logo=tailscale&logoColor=white)
![Status](https://img.shields.io/badge/status-production-brightgreen?style=flat-square)

</div>

---

## What This Is

This repository hosts the infrastructure for my personal portfolio — a site I use with real clients as a **camera and Steadicam operator**.

The site itself is simple. The infrastructure is the point.

Every decision here — from container strategy to networking model — was made the same way I'd make it in a professional engineering environment: **weighing security, cost, reliability, and maintainability against each other**, and being able to defend the outcome.

This is a career-transition project. It is also a production system I actively depend on.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    PUBLIC INTERNET                      │
└──────────────────────────┬──────────────────────────────┘
                           │ HTTPS
                           ▼
                  ┌────────────────┐
                  │   Cloudflare   │  ← CDN + DDoS protection
                  │    Tunnel      │  ← Zero inbound firewall rules
                  └───────┬────────┘
                          │ Encrypted tunnel (outbound only)
                          ▼
            ┌─────────────────────────────────┐
            │           Home Server           │  ← Private. Never directly exposed.
            │                                 │
            │  ┌───────────────────────────┐  │
            │  │       Docker Compose      │  │
            │  │                           │  │
            │  │    ┌─────────────────┐    │  │
            │  │    │   cloudflared   │    │  │  ← Opens the tunnel (outbound only)
            │  │    └────────┬────────┘    │  │
            │  │             │             │  │
            │  │             ▼             │  │
            │  │    ┌─────────────────┐    │  │
            │  │    │      NGINX      │    │  │  ← Static assets baked in
            │  │    └─────────────────┘    │  │
            │  └───────────────────────────┘  │
            └─────────────────────────────────┘
```

**Traffic never reaches the server from the public internet.** The tunnel is outbound-initiated, meaning the server has no open inbound ports. This is zero-trust networking applied at the infrastructure layer — not bolted on as an afterthought.

---

## Engineering Decisions

> These aren't just implementation choices. They reflect how I approach real-world constraints.

---

### 🔒 Zero Inbound Exposure

| Approach | Why Not |
|---|---|
| Public IP + open ports | Widens attack surface. Requires careful firewall management. |
| Reverse proxy exposed directly | Unnecessary risk for a static site. |
| **Cloudflare Tunnel** ✓ | Outbound-only connection. No public IPs. No open ports. Defense-in-depth. |

Cloudflare Tunnel means the server is **invisible to the public internet by design**, not by policy. The firewall doesn't need to be carefully managed — there's nothing to manage.

---

### 🔐 Private Network Access via Tailscale

CI/CD deployment is handled over a private WireGuard-based overlay network using Tailscale, rather than exposing SSH to the public internet.

**Why this matters:**
- Port 22 is never open to the public internet
- The GitHub Actions runner joins the private network ephemerally for the duration of the deployment, then is automatically removed. It authenticates with a Tailscale OAuth client (no auth key that expires every 90 days) and joins as a tagged node (`tag:ci`), so the tailnet ACL can limit it to the web VM on port 22
- SSH key authentication is enforced — no password auth
- Eliminates an entire class of brute force exposure

---

### 📦 Fully Baked Container Images

Content is copied into the image at build time. No volume mounts, no runtime file injection.

```dockerfile
# Assets baked in — not mounted at runtime
COPY --from=assemble /out/ /usr/share/nginx/html/
```

**Why this matters:**
- Every running container is **identical to what was tested**
- Rollbacks are a one-line change (the image tag in `.env`) and a `docker compose up -d` — no state to reconcile — and the deploy does it automatically if a new image fails its health check
- Deployment is deterministic and reproducible
- Eliminates an entire class of runtime configuration drift

I chose this to simulate how static content ships in real production pipelines.

---

### ⚖️ Docker Compose over Kubernetes (Intentionally)

Migrating from Kubernetes to Docker Compose was a deliberate infrastructure decision, not a step backwards.

The home server running this site has constrained resources. Kubernetes introduces significant overhead — control plane components, etcd, the scheduler, and associated memory usage — that is difficult to justify when the workload is a single NGINX container. Docker Compose provides the same declarative, reproducible deployment model with a fraction of the resource cost.

**The right tool for the right environment.** Knowing when *not* to use a technology is as important as knowing how to use it.

---

### 💰 Cost-Optimized Infrastructure

The site runs on a self-hosted home server — not a cloud instance. Operational cost is effectively zero beyond electricity.

Real infrastructure work happens inside real budget constraints. Designing a system that is secure, automated, and maintainable without any recurring cloud spend is a deliberate exercise in resource-conscious engineering.

---

## Repository Layout

```
.
├── .github/workflows/      # CI/CD: build, smoke test, push, deploy
├── site/                   # Static site content (HTML, CSS, media)
├── scripts/                # Image optimizer (build stage) and post-build smoke test
├── monitoring/             # Prometheus scrape config, alert rules, Grafana dashboard, firewall unit
├── default.conf            # NGINX server config (security headers, caching)
├── Dockerfile              # Multi-stage build: optimize images, then bake into NGINX
├── docker/
│   └── docker-compose.yaml # Compose service definition (lives on the server too)
└── README.md
```

---

## Deployment Model

| Property | Value |
|---|---|
| Workload type | Docker Compose service |
| Image strategy | Fully baked, versioned tags |
| External access | Cloudflare Tunnel (`cloudflared` runs in the same Compose stack; NGINX publishes no host port) |
| Remote access | Tailscale (WireGuard overlay network) |
| State | Stateless |
| Secrets required | Tunnel token in `tunnel.env` on the server (git-ignored, never in the image) |

---

## CI/CD Pipeline

Every push to `main` that changes the site, the image, the NGINX config, the scripts or the Compose file triggers a GitHub Actions workflow that:

1. Builds the Docker image (a build stage downsizes the photos, and every local asset URL in the HTML gets a content hash like `styles.css?v=1a2b3c4d5e`, so edits are never hidden by browser or Cloudflare caches; originals stay untouched in git)
2. Smoke-tests the running container: security headers are present on real pages, the CSP allows the embedded video players, cache headers are sane, and the internal metrics endpoint is not reachable on the public port. It also checks that the Compose file is valid and that its third-party images can be pulled
3. Pushes the image to Docker Hub, tagged with the git commit SHA (and `latest`)
4. Connects the runner to the private Tailscale network
5. SSHs into the home server, resets its git checkout to the deployed commit (so the compose file always matches the image; `.env` and `tunnel.env` are git-ignored and untouched), pulls the new image, and runs `docker compose up -d --wait`. If the health check fails it rolls back to the previous SHA

Pull requests run steps 1-2 only. They never push an image or deploy.

The server is never exposed to the public internet at any point in this process.

---

## Monitoring

Prometheus and Grafana watch the site without any log pipeline: nginx metrics through an exporter container, tunnel health from `cloudflared`'s own metrics endpoint, and host metrics from `node_exporter`. nginx's metrics listener is internal-only (port 8080, never published or tunnelled), and CI fails if it ever answers on the public port. The Docker-published metrics ports are limited to the Prometheus host by a small systemd unit. Scrape config, alert rules, a Grafana dashboard and setup steps are in [`monitoring/`](monitoring/README.md).

---

## Roadmap

- [x] Run `cloudflared` as a Compose service alongside NGINX
- [ ] GitOps-style deployment workflow
- [x] Automated rollback on failed health check post-deploy

---

## Why This Project Exists

I'm transitioning from a decade of work as a camera and Steadicam operator into DevOps and platform engineering. This project is the evidence of that transition — not a tutorial I followed, but a system I designed, built, and actively use.

The portfolio it hosts shows where I came from. The infrastructure it runs on shows where I'm going.

---

<div align="center">

**Built from scratch · No tutorial · Actively maintained**

</div>
