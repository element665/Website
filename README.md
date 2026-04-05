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
            ┌─────────────────────────┐
            │      Home Server        │  ← Private. Never directly exposed.
            │                         │
            │  ┌───────────────────┐  │
            │  │  Docker Compose   │  │
            │  └────────┬──────────┘  │
            │           │             │
            │        ┌──┴───┐         │
            │        │ NGINX│         │  ← Static assets baked in
            │        │      │         │
            │        └──────┘         │
            └─────────────────────────┘
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
- The GitHub Actions runner joins the private network ephemerally for the duration of the deployment, then is automatically removed
- SSH key authentication is enforced — no password auth
- Eliminates an entire class of brute force exposure

---

### 📦 Fully Baked Container Images

Content is copied into the image at build time. No volume mounts, no runtime file injection.

```dockerfile
# Assets baked in — not mounted at runtime
COPY site/ /usr/share/nginx/html/
```

**Why this matters:**
- Every running container is **identical to what was tested**
- Rollbacks are a single `docker compose up -d` with a previous image tag — no state to reconcile
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
├── site/                   # Static site content (HTML, CSS, media)
├── Dockerfile              # NGINX image — bakes in all assets at build time
├── docker-compose.yml      # Compose service definition
└── README.md
```

---

## Deployment Model

| Property | Value |
|---|---|
| Workload type | Docker Compose service |
| Image strategy | Fully baked, versioned tags |
| External access | Cloudflare Tunnel |
| Remote access | Tailscale (WireGuard overlay network) |
| State | Stateless |
| Secrets required | None at runtime |

---

## CI/CD Pipeline

Every push to `main` triggers a GitHub Actions workflow that:

1. Builds a new Docker image with a unique timestamp tag
2. Pushes the image to Docker Hub
3. Connects the runner to the private Tailscale network
4. SSHs into the home server and runs `docker compose pull && docker compose up -d`

The server is never exposed to the public internet at any point in this process.

---

## Roadmap

- [ ] Run `cloudflared` as a Compose service alongside NGINX
- [ ] Add multi-architecture image builds for ARM compatibility
- [ ] GitOps-style deployment workflow
- [ ] Automated rollback on failed health check post-deploy

---

## Why This Project Exists

I'm transitioning from a decade of work as a camera and Steadicam operator into DevOps and platform engineering. This project is the evidence of that transition — not a tutorial I followed, but a system I designed, built, and actively use.

The portfolio it hosts shows where I came from. The infrastructure it runs on shows where I'm going.

---

<div align="center">

**Built from scratch · No tutorial · Actively maintained**

</div>
