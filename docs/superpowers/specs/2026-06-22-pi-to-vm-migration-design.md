# FOSShowcase — Raspberry Pi → fos-openclaw VM Migration

**Date:** 2026-06-22
**Status:** Design (revised after spec review; pending implementation plan)
**Author:** David Hunt (with Claude)

## 1. Context & Goal

FOSShowcase is the public-facing Swift full-stack web service for `foscomputerservices.com`
(nginx + Ignite `client` + Vapor `server`). It has been running as a Docker Compose stack on a
Raspberry Pi at `10.1.2.213`. **The Pi is no longer available.**

Goal: move the stack onto an **isolated Tart Linux VM on fos-openclaw (`10.1.2.158`)** while:

- preserving the existing `docker compose` deployment model,
- rebuilding the network isolation the standalone Pi provided for free (FOSShowcase faces the
  public internet; fos-openclaw is the most sensitive host on the network),
- removing any Docker registry (Docker Hub) from the deploy loop.

This is **not** a database migration. The `foscs` PostgreSQL database already lives on
fos-openclaw (`10.1.2.158:5432`); the Pi only ran the application stack.

## 2. Current State (Pi)

- Host: Raspberry Pi, `10.1.2.213`, internal VLAN 2, arm64, bare-metal Docker + `docker compose up`.
- Stack (`docker-compose.yml`): three services — `nginx` (publishes 80/443/8081), `client`
  (internal 8082), `server` (internal 8083). Vapor services run `serve --env production`.
- nginx (`nginx.conf`):
  - `:80` → 301 redirect to `:443`
  - `:443` → `/` to `client:8082`, `/webhooks/` to `server:8083` (rate-limited)
  - `:8081` → `/` and `/webhooks/` to `server:8083` (backend / native-app API)
- **DB access (important — corrected after review):** `docker-compose.yml` **hardcodes**
  `DATABASE_HOST: host.docker.internal` (a literal, not a `${VAR}` substitution) plus
  `extra_hosts: host.docker.internal:host-gateway`. The Pi reached `foscs` on `10.1.2.158:5432`
  **via an SSH tunnel** (commit `961ef54`, "PostgreSQL via SSH tunnel"): the container hit the Pi
  host gateway, where a tunnel forwarded `:5432` to `10.1.2.158`. Runtime role `openclaw_webhook`;
  migrations role `openclaw_admin`.
- Images tagged `foscompsvcs/fos-showcase-{client,server}:latest`; every service has a `build:`
  section, so images build locally without a registry.
- TLS: cert mounted from `ssl/` into nginx. **The cert SAN is `*.foscomputerservices.com` only —
  it does NOT cover the apex `foscomputerservices.com`**, which nginx `server_name` nonetheless
  serves (pre-existing gap, see §7.1).
- Public ingress: `foscomputerservices.com` (WAN IP) → port-forward → the Pi.

## 3. Target Architecture

- **Host:** fos-openclaw (`10.1.2.158`, Apple Silicon, already a Tart host — runs `openclaw-vm`
  plus a daily Tart checkpoint service).
- **VM:** new Tart Linux VM.
  - Name: `fos-showcase`
  - OS: Ubuntu 24.04 (noble) **arm64** — matches the image bases; native arm64, no emulation.
  - Resources: ~2 vCPU / **6 GB RAM** (headroom for the Swift `--static-swift-stdlib` release
    build; idles far lower at runtime). Disk ~32 GB.
  - Static IP: **`10.1.3.10/24`**, gateway `10.1.3.1`, DNS via the VLAN's auto DNS.
  - Network attach: bridged onto **VLAN 3 "Public Servers"**.
- **Inside the VM:** Docker engine + compose plugin, running the existing 3-container stack
  (nginx 80/443/8081, client 8082 internal, server 8083 internal).
- **Disposability:** VM provisioning is fully scripted and committed; the VM is added to a Tart
  checkpoint service. The repo (plus the named secret/cert source in §7.1) is the source of truth.

### 3.1 Host prerequisite — VLAN 3 trunk (do this first)

Tart bridged networking attaches the VM to a host interface. For the VM to land on VLAN 3, the
**switch port feeding fos-openclaw's NIC must trunk VLAN 3** and the host must present the
VLAN-3-tagged bridge. The `openclaw-vm`/VLAN-20 precedent proves VLAN 20 is trunked to that port —
it does **not** prove VLAN 3 is. Verify/trunk VLAN 3 to the port before provisioning, and confirm
the VM can ARP its gateway `10.1.3.1` as the first post-boot check. This is the most likely
silent first-boot failure.

## 4. Network & Security Model

VLAN 3 "Public Servers" (`10.1.3.0/24`, gateway `10.1.3.1`, UDM Pro, zone **"Web Servers"**) has
**Isolate Network = on** and **Allow Internet Access = on**. The design punches **exactly three
holes**:

| Direction | Rule | Purpose |
|---|---|---|
| Ingress (WAN → VM) | port-forward **80, 443 only** → `10.1.3.10`; WAN→Web Servers allow | Public website (443) + TradingView webhooks (`443 /webhooks/`), HTTP→HTTPS redirect (80) |
| Egress (VM → internal) | **`10.1.3.10` → `10.1.2.158:5432` TCP only** | PostgreSQL (direct; no SSH tunnel) — nothing else internal reachable |
| Management | **local LAN(s) → `10.1.3.10:22`** (internal only; never WAN) | Deploy / admin over SSH (option A), restricted to local LANs |

- Internet egress remains open (VLAN already allows it) for base-image pulls, apt, SPM fetches, NTP,
  and DNS resolution — all outbound-to-internet, requiring **no** inter-VLAN holes.
- Nothing internal initiates to the VM (the trading pipeline reads `webhook.tv_alerts` from the DB,
  not from FOSShowcase). Inbound from internal trust zones stays default-deny.

### 4.1 Companion change in `openclaw-config` (outside this repo)

`deploy/postgres/setup-postgres.sh` currently authorizes only `10.1.2.0/24` and `10.1.20.0/24` in
`pg_hba.conf`. Add an **idempotent block authorizing `10.1.3.10/32`** (least privilege; `/32` not
`/24`) with `scram-sha-256`, *in the script* — a manual `pg_hba` edit would be clobbered on the next
infra run (openclaw-config rule #10). Apply with `pg_reload_conf()` / `pg_ctl reload` — **reload,
not restart**. Without this, Postgres rejects the VM even with the firewall open.

### 4.2 Port 8081 — decided: not publicly forwarded

Both 443 and 8081 are nginx TLS listeners (same cert, same `/webhooks/` rate-limiting) — 8081 is
**not** a raw/un-fronted port. They split only by upstream-at-root: `:443 /` → `client:8082`
(website), `:8081 /` → `server:8083` (backend API for native apps).

**Decision:** native apps are out of scope for this migration, so **8081 gets no WAN port-forward.**
The website and TradingView webhooks both arrive on 443. The 8081 listener still runs inside the VM
(reachable on the VLAN if ever needed) but is not exposed to the internet — one fewer public hole.
If native-app support over the internet is needed later, add the forward then, or serve the API
under a path on 443 (e.g. `/api/`) for a single public port.

## 5. Database (connection retargeted, DB unchanged)

`foscs` stays on `10.1.2.158:5432`. The SSH tunnel is retired; the VM connects **directly** over the
firewall egress + `pg_hba` pinhole. This requires a small, deliberate **compose change** (see §11 —
this is in scope, contrary to a naive "no app changes" reading):

- Change `DATABASE_HOST: host.docker.internal` → `DATABASE_HOST: ${DATABASE_HOST:-10.1.2.158}` so
  `.env` can set it, and put `DATABASE_HOST=10.1.2.158` in `.env`.
- Remove the now-dead `extra_hosts: host.docker.internal:host-gateway`.

Roles unchanged: `openclaw_webhook` (runtime, INSERT+SELECT on `webhook.tv_alerts`), `openclaw_admin`
(migrations). Both the egress firewall rule and `pg_hba` must authorize `10.1.3.10`.

## 6. Image Build — No Registry

Deploy is **`docker compose up -d --build` inside the VM** — images build locally, never pushed or
pulled from a registry. Docker Hub is eliminated as a *distribution* dependency; `foscompsvcs/*`
tags become plain local tags (optionally retagged `fos-showcase-{server,client}:local`). The only
residual registry touch is **base-image pulls at build time** (`swift:6.2.3-noble`, `ubuntu:noble`,
`nginx:1.28.0`) — build-time only, cached, not a runtime dependency. The 6 GB VM sizing covers the
transient Swift build spike.

## 7. Provisioning & Deploy (lives in FOSShowcase repo)

New `deploy/` directory in the FOSShowcase repo (repo is source of truth, VM disposable):

- `deploy/provision-vm.sh` — create the `fos-showcase` Tart VM, attach the VLAN-3 bridge, set static
  IP `10.1.3.10`, install Docker, enable NTP. Docker install uses **Docker's official apt repo**
  (`download.docker.com/linux/ubuntu`, arm64) installing `docker-ce docker-ce-cli containerd.io
  docker-compose-plugin` (the Ubuntu `docker.io` package does **not** ship `docker compose` v2), and
  adds the deploy user to the `docker` group. Enable `chrony`/`systemd-timesyncd` — HMAC and TLS are
  clock-sensitive and a fresh VM can boot skewed.
- `deploy/deploy.sh` — pull `.env` + `ssl/` from their canonical source (§7.1), sync the repo to the
  VM over the management SSH channel, run `docker compose up -d --build`.
- Daily checkpoints: a host LaunchAgent `com.foscs.tart-fos-showcase-checkpoint.plist` that invokes
  the existing `openclaw-config/deploy/tart-daily-checkpoint.sh` **by absolute path** with
  `SOURCE_VM=fos-showcase` (cross-repo call, documented — preferred over duplicating the script).
  Note `tart clone` of a live VM may need a brief stop/snapshot for a consistent checkpoint; confirm
  how the existing `openclaw-vm` service handles this and mirror it.
- `docs/runbook-pi-to-vm.md` — operational runbook covering the UDM Pro firewall/port-forward
  changes, the `openclaw-config` `pg_hba` change, and the SYSTEM-MAP.md update (§8).

### 7.1 SSL & Secrets (named source, not "out of band")

`.env` and `ssl/` are gitignored, so "VM rebuildable from scratch" requires a **named canonical
source**, mirroring the openclaw-config `~/.openclaw/.env` + `init-env.sh` doctrine:

- Define a master location on the dev Mac for FOSShowcase's `.env` and `ssl/` (e.g.
  `~/.foscs/fosshowcase/{.env,ssl/}`); `deploy.sh` pulls from there. Deliver with modes **600** for
  the cert key and `.env`.
- **Cert (decided — reissue):** the current cert is wildcard-only (`*.foscomputerservices.com`,
  expires **2026-07-20**) and does not cover the apex. A **new SAN cert covering both the apex
  `foscomputerservices.com` and `*.foscomputerservices.com`** will be generated and placed in `ssl/`
  (and at the canonical source above) as part of the migration. Verification (§9) tests the exact
  production hostnames over TLS.

## 8. Migration / Cutover Sequence

The Pi is **gone — there is no live fallback** — so the VM is validated in full before public
traffic is flipped.

1. **Prereq:** trunk VLAN 3 to the host port (§3.1).
2. Provision the `fos-showcase` VM on VLAN 3 (`10.1.3.10`); confirm it ARPs `10.1.3.1` and has
   correct clock.
3. Apply the `openclaw-config` `pg_hba` change (`10.1.3.10/32`) and **reload** Postgres; add the UDM
   egress pinhole (`10.1.3.10` → `10.1.2.158:5432`).
4. Apply the compose `DATABASE_HOST` change (§5); deliver `.env` + `ssl/`; deploy
   (`docker compose up -d --build`).
5. **Internal validation against `10.1.3.10` directly** (before WAN exposure): website loads; DB
   connects directly (no tunnel); a simulated authenticated `/webhooks/` POST INSERTs into
   `webhook.tv_alerts`.
6. Add the WAN port-forwards (**80/443 only** — no 8081, per §4.2) + WAN→Web Servers allow. DNS
   already resolves to the WAN IP (no change unless it was a LAN-mapped record).
7. **External validation:** a real TradingView test alert lands in `tv_alerts`; the native-app
   endpoint responds; TLS verified with `openssl s_client` against the *exact* production hostnames.
8. Add the VM to the Tart checkpoint service; update **SYSTEM-MAP.md** (FOSShowcase now
   `10.1.3.10` / VLAN 3; DB firewall row gains VLAN 3) per openclaw-config rule #8.

## 9. Verification

- TLS via `openssl s_client` (not curl) against each production hostname — catches the apex/SAN gap.
- End-to-end TradingView alert → `webhook.tv_alerts` round-trip, confirmed via `webhook_read_alerts`.
- **Isolation tests (both directions of the egress rule):**
  - Positive: VM reaches `10.1.2.158:5432`.
  - Negative (scope): VM is **refused** to `10.1.2.158:3300` (fos-db MCP) and other internal ports —
    proving the egress allow is port-scoped to 5432, not host-wide.
  - Negative (host): VM cannot reach a non-Postgres internal host at all.

## 10. Risks & Mitigations

- **No rollback to the Pi.** Mitigated by full pre-cutover validation against the direct VM IP.
- **`DATABASE_HOST` retarget / tunnel removal** is a behavior change. Mitigated by step 5 internal
  validation confirming a direct (non-tunnel) DB connection before WAN exposure.
- **Cert apex/SAN gap + 2026-07-20 expiry.** Mitigated by reissuing a SAN cert during the window.
- **VLAN 3 not trunked to the host port.** Mitigated by the §3.1 prerequisite + ARP check.
- **Resource pressure on the Mac Mini.** Mitigated by local-build-only and modest steady-state
  footprint; the 6 GB is a deploy-time spike. Watch host load.
- **Clock skew on a fresh VM.** Mitigated by NTP enablement + clock check (step 2).

## 11. Decisions Made

- Runtime: **Tart Linux VM** (Docker-on-host rejected for blast-radius; Lima rejected — Tart matches
  existing tooling).
- Network: **VLAN 3 "Public Servers"**, static `10.1.3.10`, three firewall holes only.
- Public ingress: **80/443 only** — 8081 (native-app backend API) is not WAN-forwarded; native
  apps are out of scope for this migration.
- Management access: **option A** — SSH pinhole to `10.1.3.10:22` allowed **only from local LAN(s)**,
  never WAN.
- Cert: **reissue a SAN cert covering apex + wildcard** (replaces the wildcard-only cert).
- Deploy model: **build-in-VM, no registry** (`docker compose up -d --build`).
- DB connection: **direct to `10.1.2.158:5432`**, SSH tunnel retired (requires the §5 compose edit).
- VM sizing: ~2 vCPU / 6 GB / ~32 GB disk.
- Provisioning scripts + runbook: **in the FOSShowcase repo**; `pg_hba` change in openclaw-config.

## 12. Scope

**In scope (app repo):** a minimal `docker-compose.yml` edit (`DATABASE_HOST` → `${...:-10.1.2.158}`,
remove dead `extra_hosts`); possible cert reissue; new `deploy/` scripts + runbook.
**In scope (openclaw-config):** `pg_hba` `/32` authorization; SYSTEM-MAP.md update.
**Out of scope:** migrating `foscs` PostgreSQL (already on fos-openclaw); FOSShowcase application
logic; re-architecting public ingress beyond retargeting port-forwards.
