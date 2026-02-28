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

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)
![NGINX](https://img.shields.io/badge/NGINX-009639?style=flat-square&logo=nginx&logoColor=white)
![Cloudflare](https://img.shields.io/badge/Cloudflare_Tunnel-F38020?style=flat-square&logo=cloudflare&logoColor=white)
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
            │    Kubernetes Cluster   │  ← Private. Never directly exposed.
            │                         │
            │  ┌───────────────────┐  │
            │  │     Service       │  │
            │  └────────┬──────────┘  │
            │           │             │
            │    ┌──────┴──────┐      │
            │    ▼             ▼      │
            │ ┌──────┐    ┌──────┐    │
            │ │ NGINX│    │ NGINX│    │  ← 2 replicas
            │ │ Pod  │    │ Pod  │    │  ← Static assets baked in
            │ └──────┘    └──────┘    │
            └─────────────────────────┘
```

**Traffic never reaches the cluster from the public internet.** The tunnel is outbound-initiated, meaning the cluster has no open inbound ports. This is zero-trust networking applied at the infrastructure layer — not bolted on as an afterthought.

---

## Engineering Decisions

> These aren't just implementation choices. They reflect how I approach real-world constraints.

---

### 🔒 Zero Inbound Exposure

| Approach | Why Not |
|---|---|
| LoadBalancer + public IP | Opens inbound firewall rules. Widens attack surface. |
| NodePort | Exposes cluster ports directly. Unnecessary risk for a static site. |
| **Cloudflare Tunnel** ✓ | Outbound-only connection. No public IPs. No open ports. Defense-in-depth. |

Cloudflare Tunnel means the cluster is **invisible to the public internet by design**, not by policy. The firewall doesn't need to be carefully managed — there's nothing to manage.

---

### 📦 Fully Baked Container Images

Content is copied into the image at build time. No ConfigMaps, no volume mounts, no runtime file injection.

```dockerfile
# Assets baked in — not mounted at runtime
COPY site/ /usr/share/nginx/html/
```

**Why this matters:**
- Every running container is **identical to what was tested**
- Rollbacks are a single `kubectl rollout undo` — no state to reconcile
- Deployment is deterministic and reproducible
- Eliminates an entire class of runtime configuration drift

I chose this to simulate how static content ships in real production pipelines.

---

### 🏗️ Multi-Architecture Builds

Images are built and published as multi-arch manifests, not single-platform binaries.

**Why this matters:** Architecturally-incompatible images fail silently in some environments and loudly in others. Building multi-arch by default means the image works wherever it's pulled — no platform-specific debugging, no surprise failures on ARM nodes.

---

### ⚖️ Kubernetes for a Static Site (Intentionally)

Running Kubernetes for a static site is unusual. That's the point.

The goal isn't to use the right tool for the simplest job — it's to **practice the deployment patterns, operational workflows, and failure modes** that appear constantly in production environments. The cluster can be destroyed and rebuilt from scratch with no data loss and no manual steps.

---

### 🔁 Two Replicas as a Standard Baseline

The deployment runs two NGINX pods at all times.

No single point of failure. Rolling updates don't cause downtime. A pod being evicted or crashing is handled automatically. This is not over-engineering — running a single replica is the thing that requires justification.

---

### 💰 Cost-Optimized Infrastructure

The cluster runs on appropriately-sized nodes — not oversized instances purchased for headroom.

Real infrastructure work happens inside real budget constraints. Choosing cost-appropriate compute while maintaining availability and security is a core skill, not a compromise. This system was designed to be lean from the start, not downsized after the fact.

---

## Repository Layout

```
.
├── site/                   # Static site content (HTML, CSS, media)
├── Dockerfile              # NGINX image — bakes in all assets at build time
├── k8s/
│   └── pr_site.yaml        # Kubernetes service & deployment configuration
└── README.md
```

---

## Deployment Model

| Property | Value |
|---|---|
| Workload type | Kubernetes Deployment |
| Replicas | 2 |
| Image strategy | Fully baked, versioned tags |
| External access | Cloudflare Tunnel |
| Service type | ClusterIP (internal only) |
| State | Stateless |
| Secrets required | None |

---

## Roadmap

- [ ] Run `cloudflared` as a pod inside the cluster (eliminates external dependency)
- [ ] Migrate fully to ClusterIP service type
- [ ] GitOps-style deployment workflow
- [ ] Helm chart for repeatable installs

---

## Why This Project Exists

I'm transitioning from a decade of work as a camera and Steadicam operator into DevOps and platform engineering. This project is the evidence of that transition — not a tutorial I followed, but a system I designed, built, and actively use.

The portfolio it hosts shows where I came from. The infrastructure it runs on shows where I'm going.

---

<div align="center">

**Built from scratch · No tutorial · Actively maintained**

*MIT License*

</div>