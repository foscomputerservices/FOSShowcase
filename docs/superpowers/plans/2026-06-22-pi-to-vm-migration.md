# FOSShowcase Pi → fos-openclaw VM Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the FOSShowcase Docker stack off the decommissioned Raspberry Pi onto an isolated Tart Linux VM on fos-openclaw (VLAN 3 "Public Servers", `10.1.3.10`), preserving the `docker compose` deploy model, with a direct firewall-pinholed Postgres connection and exactly three firewall holes.

**Architecture:** A dedicated Ubuntu 24.04 arm64 Tart VM on fos-openclaw runs the existing 3-container compose stack (nginx/client/server) unchanged. Images build in the VM (`docker compose up -d --build`, no registry). The VM sits on the isolated UniFi DMZ VLAN 3; it reaches `foscs` Postgres on `10.1.2.158:5432` directly through a single egress firewall pinhole plus a `pg_hba` `/32` grant (the Pi's SSH tunnel is retired). Public ingress is WAN 80/443 only.

**Tech Stack:** Tart (macOS Apple-Silicon VM tool), Docker + compose v2, Ubuntu 24.04 arm64, netplan, nginx, Vapor/Swift, PostgreSQL 18, UniFi UDM Pro firewall, macOS `launchd`.

**Spec:** `docs/superpowers/specs/2026-06-22-pi-to-vm-migration-design.md`

---

## Repos & surfaces

This plan touches **two repos and live infra**:

- **FOSShowcase** (this repo, branch `migration/pi-to-vm`): `docker-compose.yml` edit, new `deploy/` scripts, checkpoint plist, runbook.
- **openclaw-config**: `deploy/postgres/setup-postgres.sh` `pg_hba` grant, `docs/SYSTEM-MAP.md` topology update. Commit these on a matching branch (e.g. `feat/fosshowcase-vlan3`).
- **Live infra (runbook-driven, Phase 2):** UniFi UDM Pro (VLAN-3 trunk, DHCP reservation, firewall rules, port-forward), fos-openclaw host (Tart provisioning), the production `foscs` DB (live `pg_reload_conf`). These require host/UDM access and are executed from the runbook, not committed.

## File structure

| Path | Repo | Responsibility |
|---|---|---|
| `docker-compose.yml` (modify) | FOSShowcase | Make `DATABASE_HOST` `.env`-overridable; drop dead `extra_hosts` |
| `deploy/env.example` (create) | FOSShowcase | Document required runtime env vars |
| `deploy/provision-vm.sh` (create) | FOSShowcase | Create + network + base-provision the Tart VM |
| `deploy/com.foscs.tart-fos-showcase.plist` (create) | FOSShowcase | Keep `tart run fos-showcase` alive across host reboots (mirrors openclaw-vm) |
| `deploy/deploy.sh` (create) | FOSShowcase | Deliver secrets/certs/repo to VM; `compose up -d --build` |
| `deploy/com.foscs.tart-fos-showcase-checkpoint.plist` (create) | FOSShowcase | Daily Tart checkpoint LaunchAgent (host) |
| `docs/runbook-pi-to-vm.md` (create) | FOSShowcase | Operational runbook: infra prereqs, firewall, cutover, verification, rollback |
| `deploy/postgres/setup-postgres.sh` (modify) | openclaw-config | Idempotent `pg_hba` grant for `10.1.3.10/32` |
| `docs/SYSTEM-MAP.md` (modify) | openclaw-config | FOSShowcase → `10.1.3.10`/VLAN 3; DB firewall row |

## Conventions for this plan

These are infra scripts, not unit-testable application code. "Verify" steps use `bash -n` (syntax), `shellcheck` (lint), `plutil`/`docker compose config` (artifact validation), and idempotency re-runs. **Live behavior is validated in Phase 2 against the running VM** — there is no Pi fallback, so Phase 2 validates fully on the direct VM IP before any WAN exposure.

**Commit policy:** every `git commit` in this plan must end with the trailer
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` (omitted from the snippets below for brevity).

Decided parameters (from spec):
- VM name `fos-showcase`; Ubuntu 24.04 arm64; ~2 vCPU / 6 GB / 32 GB disk.
- Static IP `10.1.3.10/24`, gw `10.1.3.1`, VLAN 3, zone "Web Servers".
- VM repo path `/opt/fosshowcase`; VM admin user `admin` (Tart Ubuntu default — harden with SSH key, disable password).
- Canonical secret/cert source on dev Mac: `~/.foscs/fosshowcase/{.env,ssl/}` (mode 600).

---

## Phase 1 — Repo artifacts (offline, committable)

### Task 1: Retarget DB connection in compose

**Files:**
- Modify: `docker-compose.yml` (server `environment` + `extra_hosts`)
- Create: `deploy/env.example`

- [ ] **Step 1: Edit `docker-compose.yml`** — make `DATABASE_HOST` overridable and remove the dead tunnel mapping.

Change:
```yaml
      DATABASE_HOST: host.docker.internal
```
to:
```yaml
      DATABASE_HOST: ${DATABASE_HOST:-10.1.2.158}
```
Delete the `extra_hosts` block from the `server` service:
```yaml
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

- [ ] **Step 2: Create `deploy/env.example`**

```bash
# FOSShowcase runtime environment (copy to the canonical source ~/.foscs/fosshowcase/.env, mode 600)
LOG_LEVEL=info
DATABASE_HOST=10.1.2.158
DATABASE_PORT=5432
DATABASE_NAME=foscs
DATABASE_USER=openclaw_webhook
DATABASE_PASSWORD=__set_me__            # POSTGRES_WEBHOOK_PASSWORD
MIGRATION_DATABASE_USER=openclaw_admin
MIGRATION_DATABASE_PASSWORD=__set_me__  # POSTGRES_ADMIN_PASSWORD
WEBHOOK_SECRET=__set_me__               # TradingView HMAC
```

- [ ] **Step 3: Validate compose parses with the override**

Run: `DATABASE_HOST=10.1.2.158 POSTGRES_WEBHOOK_PASSWORD=x POSTGRES_ADMIN_PASSWORD=x WEBHOOK_SECRET=x docker compose config | grep -A2 'DATABASE_HOST'`
Expected: resolved value shows `DATABASE_HOST: 10.1.2.158` and **no** `extra_hosts` under `server`.

- [ ] **Step 4: Commit**

```bash
git add docker-compose.yml deploy/env.example
git commit -m "feat(deploy): direct DB host via DATABASE_HOST env; drop SSH-tunnel extra_hosts"
```

---

### Task 2: VM provisioning script

**Files:**
- Create: `deploy/provision-vm.sh`

- [ ] **Step 1: Write `deploy/provision-vm.sh`** (runs ON fos-openclaw, where Tart lives)

```bash
#!/bin/bash
set -euo pipefail

# Provision the fos-showcase Tart VM on the VLAN-3 "Public Servers" DMZ.
# Run ON fos-openclaw (Tart host). Idempotent where practical.
#
# Prereqs handled in the runbook BEFORE this runs:
#   - VLAN 3 trunked to the host's switch port
#   - DHCP reservation OR pool-exclusion for 10.1.3.10 on the UDM Pro

VM_NAME="${VM_NAME:-fos-showcase}"
BASE_IMAGE="${BASE_IMAGE:-ghcr.io/cirruslabs/ubuntu:24.04}"
VM_CPU="${VM_CPU:-2}"
VM_MEM="${VM_MEM:-6144}"           # MB; headroom for the Swift release build
VM_DISK="${VM_DISK:-32}"           # GB
# REQUIRED: the exact interface token from `tart run --net-bridged=list` on the host.
# A VLAN-3 tagged interface is NOT a friendly name — discover/create it first (runbook §1).
VLAN_IFACE="${VLAN_IFACE:?set VLAN_IFACE to the exact token from 'tart run --net-bridged=list'}"
TART_BIN="${TART_BIN:-tart}"

command -v "$TART_BIN" >/dev/null || { echo "tart not found"; exit 1; }

if "$TART_BIN" list --quiet | grep -qx "$VM_NAME"; then
  echo "VM $VM_NAME already exists — skipping clone."
else
  echo "Cloning $BASE_IMAGE -> $VM_NAME"
  "$TART_BIN" clone "$BASE_IMAGE" "$VM_NAME"
fi

"$TART_BIN" set "$VM_NAME" --cpu "$VM_CPU" --memory "$VM_MEM"
# --disk-size only GROWS a disk; setting it <= the base image's size errors. Apply
# best-effort, then verify+grow the guest filesystem in-guest (Task 9: growpart/resize2fs).
"$TART_BIN" set "$VM_NAME" --disk-size "$VM_DISK" \
  || echo "  (disk already >= ${VM_DISK}G or set skipped — verify with 'df -h' in-guest)"

echo "Starting $VM_NAME bridged to '$VLAN_IFACE' (run under launchd/tmux for persistence in prod)"
echo "  $TART_BIN run \"$VM_NAME\" --net-bridged=\"$VLAN_IFACE\" --no-graphics &"
echo ""
echo "After boot, finish in-guest provisioning via SSH (see provision-guest snippet in runbook):"
echo "  - netplan static 10.1.3.10/24 gw 10.1.3.1"
echo "  - Docker CE + docker-compose-plugin from download.docker.com (arm64)"
echo "  - enable systemd-timesyncd (clock-sensitive HMAC/TLS)"
```

> Note: the **in-guest** steps (netplan, Docker install, NTP) are documented as a copy-paste block in the runbook (Task 7) rather than baked here, because they run inside the VM over SSH and depend on the VM's first-boot credentials. Keeping them in the runbook keeps `provision-vm.sh` host-side and idempotent.

- [ ] **Step 2: Lint**

Run: `bash -n deploy/provision-vm.sh && shellcheck deploy/provision-vm.sh`
Expected: no errors (shellcheck: no warnings above info).

- [ ] **Step 3: Commit**

```bash
chmod +x deploy/provision-vm.sh
git add deploy/provision-vm.sh
git commit -m "feat(deploy): Tart VM provisioning for fos-showcase on VLAN 3"
```

---

### Task 2b: VM run-persistence LaunchAgent

**Files:**
- Create: `deploy/com.foscs.tart-fos-showcase.plist`

`provision-vm.sh` deliberately does not start the VM (startup needs a persistent supervisor, not a one-shot). The VM must survive host reboots like `openclaw-vm` does.

- [ ] **Step 1: Confirm the openclaw-vm run mechanism on fos-openclaw** and mirror it.

Run (on fos-openclaw): `ls ~/Library/LaunchAgents/ | grep -i tart; launchctl list | grep -i openclaw`
Expected: identify the LaunchAgent (or other supervisor) that keeps `openclaw-vm` running. If it differs from a `tart run` LaunchAgent, mirror that mechanism instead of the plist below.

- [ ] **Step 2: Write `deploy/com.foscs.tart-fos-showcase.plist`** (KeepAlive supervisor for `tart run`; substitute the real `--net-bridged` token).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.foscs.tart-fos-showcase</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/tart</string>
        <string>run</string>
        <string>fos-showcase</string>
        <string>--net-bridged=REPLACE_WITH_VLAN3_INTERFACE</string>
        <string>--no-graphics</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/tart-fos-showcase.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/tart-fos-showcase.err.log</string>
</dict>
</plist>
```

- [ ] **Step 3: Validate** — `plutil -lint deploy/com.foscs.tart-fos-showcase.plist` → `OK`.

- [ ] **Step 4: Commit**

```bash
git add deploy/com.foscs.tart-fos-showcase.plist
git commit -m "feat(deploy): KeepAlive LaunchAgent to keep fos-showcase VM running"
```

> Like the checkpoint plist, this is **not** deployed by openclaw-config's `deploy-all.sh` — it is installed manually on the host (runbook §3). The `--net-bridged` token must match the interface discovered in Task 8.

---

### Task 3: Deploy script

**Files:**
- Create: `deploy/deploy.sh`

- [ ] **Step 1: Write `deploy/deploy.sh`** (runs from the dev Mac on the local LAN → VM:22)

```bash
#!/bin/bash
set -euo pipefail

# Deliver secrets/certs/repo to the fos-showcase VM and (re)deploy the stack.
# Run from the dev Mac (local LAN — allowed by the management firewall pinhole).

VM_HOST="${VM_HOST:-admin@10.1.3.10}"
VM_PATH="${VM_PATH:-/opt/fosshowcase}"
SRC_SECRETS="${SRC_SECRETS:-$HOME/.foscs/fosshowcase}"   # canonical .env + ssl/ source
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new)

# Cert/key filenames MUST match nginx.conf's hardcoded paths
# (ssl_certificate foscomputerservices.com.crt / ssl_certificate_key foscomputerservices.com.key).
# The reissued SAN cert must keep these exact names or nginx won't start.
[ -f "$SRC_SECRETS/.env" ] || { echo "Missing $SRC_SECRETS/.env"; exit 1; }
[ -f "$SRC_SECRETS/ssl/foscomputerservices.com.crt" ] || { echo "Missing cert in $SRC_SECRETS/ssl"; exit 1; }
[ -f "$SRC_SECRETS/ssl/foscomputerservices.com.key" ] || { echo "Missing key in $SRC_SECRETS/ssl"; exit 1; }

echo "==> Ensuring remote path"
ssh "${SSH_OPTS[@]}" "$VM_HOST" "sudo mkdir -p '$VM_PATH' && sudo chown \$(id -un) '$VM_PATH'"

echo "==> Syncing repo (excluding build/vcs/secrets)"
rsync -az --delete \
  --exclude '.git' --exclude '.build' --exclude 'ssl' --exclude '.env' \
  -e "ssh ${SSH_OPTS[*]}" \
  "$REPO_ROOT/" "$VM_HOST:$VM_PATH/"

echo "==> Delivering secrets + certs (mode 600)"
rsync -az -e "ssh ${SSH_OPTS[*]}" "$SRC_SECRETS/.env" "$VM_HOST:$VM_PATH/.env"
rsync -az -e "ssh ${SSH_OPTS[*]}" "$SRC_SECRETS/ssl/" "$VM_HOST:$VM_PATH/ssl/"
ssh "${SSH_OPTS[@]}" "$VM_HOST" "chmod 600 '$VM_PATH/.env' '$VM_PATH'/ssl/*.key"

echo "==> Building + starting stack"
ssh "${SSH_OPTS[@]}" "$VM_HOST" "cd '$VM_PATH' && docker compose up -d --build"

echo "==> Container status"
ssh "${SSH_OPTS[@]}" "$VM_HOST" "cd '$VM_PATH' && docker compose ps"
```

- [ ] **Step 2: Lint**

Run: `bash -n deploy/deploy.sh && shellcheck deploy/deploy.sh`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
chmod +x deploy/deploy.sh
git add deploy/deploy.sh
git commit -m "feat(deploy): deploy.sh — sync repo+secrets to VM and compose up --build"
```

---

### Task 4: Daily checkpoint LaunchAgent

**Files:**
- Create: `deploy/com.foscs.tart-fos-showcase-checkpoint.plist`

- [ ] **Step 1: Write the plist** (mirrors `com.foscs.tart-openclaw-checkpoint.plist`; calls the openclaw-config-deployed checkpoint script by its host path; offset to 02:30 so it doesn't collide with openclaw-vm's 02:00).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.foscs.tart-fos-showcase-checkpoint</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/david/.foscs/scripts/tart-daily-checkpoint.sh</string>
        <string>fos-showcase</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>RETENTION_COUNT</key>
        <string>7</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>30</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/tart-fos-showcase-checkpoint.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/tart-fos-showcase-checkpoint.err.log</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
```

> Cross-repo dependency (documented): `tart-daily-checkpoint.sh` lives in openclaw-config and is deployed to `~/.foscs/scripts/` on fos-openclaw by `openclaw-config/deploy/deploy-all.sh`. It is already parameterized by source VM name, so `fos-showcase` works with no script change. `tart clone` of a running VM yields a crash-consistent checkpoint; acceptable here (same as openclaw-vm).
>
> **This plist is NOT auto-deployed.** `openclaw-config/deploy/deploy-all.sh` only ships `com.foscs.tart-openclaw-checkpoint.plist`. Both this checkpoint plist and the run plist (Task 2b) are installed manually on the host (runbook §3/§7). Optionally, a follow-up can extend `deploy-all.sh` to also ship the two `fos-showcase` plists so they're not orphaned at the next deploy-all run.

- [ ] **Step 2: Validate plist**

Run: `plutil -lint deploy/com.foscs.tart-fos-showcase-checkpoint.plist`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add deploy/com.foscs.tart-fos-showcase-checkpoint.plist
git commit -m "feat(deploy): daily Tart checkpoint LaunchAgent for fos-showcase"
```

---

### Task 5: pg_hba grant (openclaw-config repo)

**Files:**
- Modify: `deploy/postgres/setup-postgres.sh` (after the `10.1.2.0/24` LAN block, ~line 99)

- [ ] **Step 1: Add an idempotent `/32` block** matching the existing style.

```bash
# FOSShowcase VM (VLAN 3 DMZ) — webhook ingester, least-privilege /32
# NOTE: fixed-string grep. The existing blocks above grep "<CIDR>.*foscs.*scram"
# but write "host foscs all <CIDR> scram" — foscs precedes the CIDR, so their
# guard NEVER matches and they append a duplicate on every run (confirmed bug).
# Do not copy that pattern.
if grep -qF "10.1.3.10/32" "$PG_HBA"; then
    echo "    FOSShowcase entry (10.1.3.10/32) already present — skipping."
else
    echo "host    foscs    all    10.1.3.10/32    scram-sha-256" >> "$PG_HBA"
    echo "    Added FOSShowcase entry (10.1.3.10/32)."
fi
```

> Optional hardening (note for the executor): the three existing guards (loopback,
> `10.1.20.0/24`, `10.1.2.0/24`) share the same idempotency bug. Fixing them is out of
> scope for this migration but worth a follow-up ticket; do not silently rewrite them here.

- [ ] **Step 2: Lint**

Run: `bash -n deploy/postgres/setup-postgres.sh`
Expected: no errors.

- [ ] **Step 3: Commit (openclaw-config branch)**

```bash
git add deploy/postgres/setup-postgres.sh
git commit -m "feat(postgres): authorize FOSShowcase VM 10.1.3.10/32 in pg_hba"
```

> ⚠️ Live application is **not** done by re-running this script on prod (its step 4 does `brew services restart postgresql@18`, which bounces the production DB). The runbook applies just the new line to the live `pg_hba.conf` and calls `SELECT pg_reload_conf();`. This script edit is for durable rebuilds.

---

### Task 6: SYSTEM-MAP.md topology update (openclaw-config repo)

**Files:**
- Modify: `docs/SYSTEM-MAP.md`

- [ ] **Step 1: Update FOSShowcase references** — replace `10.1.2.213` / "VLAN 2" / "Docker" host context with `10.1.3.10` on VLAN 3 "Public Servers" (Tart VM on fos-openclaw). Update the services/firewall tables: the FOSShowcase row (~line 469) and the PostgreSQL endpoint row (~line 966). **The endpoint row's access column currently reads "Loopback + VLAN 20" — this is already stale** (the live `pg_hba` also authorizes `10.1.2.0/24`). Correct it to reflect loopback + `10.1.20.0/24` + `10.1.2.0/24` **and** add the new `10.1.3.10/32`. Update the relevant mermaid topology blocks (FOSShowcase subgraph ~line 73) and the prose reference at ~line 330.

- [ ] **Step 2: Sanity check** there are no remaining stale `10.1.2.213` FOSShowcase references.

Run: `grep -n "10.1.2.213" docs/SYSTEM-MAP.md`
Expected: no FOSShowcase matches (or none at all).

- [ ] **Step 3: Commit (openclaw-config branch)**

```bash
git add docs/SYSTEM-MAP.md
git commit -m "docs(system-map): FOSShowcase now on VLAN 3 (10.1.3.10) Tart VM"
```

---

### Task 7: Cutover runbook

**Files:**
- Create: `docs/runbook-pi-to-vm.md`

- [ ] **Step 1: Write the runbook** with these sections (full commands, copy-paste ready):

1. **Infra prerequisites (UDM Pro):**
   - Trunk VLAN 3 to the fos-openclaw switch port; confirm the host can present a `VLAN 3` bridged interface for Tart.
   - **Exclude `10.1.3.10` from the DHCP pool** (pool is `10.1.3.6–254`; shrink the start to `.11` or otherwise carve out `.10`). A DHCP *reservation* is **not** sufficient here because the guest uses a **static** netplan address — the goal is to guarantee no other host is ever leased `.10`. Confirm `.10` is unused (`arping`/ping) before bringing up the static config.
   - Generate the new SAN cert (apex + `*.foscomputerservices.com`). It **must** be written with the exact filenames `foscomputerservices.com.crt` and `foscomputerservices.com.key` (nginx.conf hardcodes these). Place at `~/.foscs/fosshowcase/ssl/` on the dev Mac.
2. **Firewall rules ("Web Servers" zone) — exactly three holes:**
   - Egress: `10.1.3.10` → `10.1.2.158:5432` TCP allow; default-deny rest to internal zones.
   - Ingress: WAN port-forward `80,443` → `10.1.3.10`; WAN→Web Servers allow for 80/443. **No 8081.**
   - Management: local LAN(s) → `10.1.3.10:22` allow; never WAN.
3. **In-guest provisioning block** (SSH into the VM after first boot): netplan static `10.1.3.10/24` gw `10.1.3.1`; Docker CE + `docker-compose-plugin` from `download.docker.com/linux/ubuntu` (arm64); add `admin` to `docker` group; enable `systemd-timesyncd`; SSH-key auth + disable password.
4. **Live pg_hba apply (no restart):** append `host foscs all 10.1.3.10/32 scram-sha-256` to the prod `pg_hba.conf`, then `psql -c "SELECT pg_reload_conf();"` (psql at `/opt/homebrew/Cellar/postgresql@18/18.2/bin/psql`).
5. **Cutover sequence** (mirrors spec §8): provision → pg_hba+egress → deploy → internal validation on `10.1.3.10` → flip WAN port-forward → external validation → checkpoint install + SYSTEM-MAP.
6. **Verification** (spec §9): `openssl s_client -connect <host>:443 -servername foscomputerservices.com` for apex AND a subdomain; TradingView test alert → `webhook.tv_alerts` via `webhook_read_alerts`; isolation negatives — VM refused to `10.1.2.158:3300` and to a non-Postgres internal host; positive — VM reaches `10.1.2.158:5432`.
7. **Checkpoint install:** copy the plist to `~/Library/LaunchAgents/` on fos-openclaw and `launchctl load` it.
8. **Rollback:** no Pi fallback — rollback = revert the WAN port-forward (site goes dark) and debug on the direct IP. Emphasize: do not flip WAN until internal validation passes.

- [ ] **Step 2: Commit**

```bash
git add docs/runbook-pi-to-vm.md
git commit -m "docs(runbook): Pi -> VM cutover runbook (firewall, provisioning, verification)"
```

---

## Phase 2 — Execution (live infra, runbook-driven)

> These tasks run against the UDM Pro, the fos-openclaw host, and the production DB. They require host/UDM access and are gated on a human. Follow `docs/runbook-pi-to-vm.md`. **No WAN exposure until internal validation (Task 10) passes** — there is no Pi to fall back to.

### Task 8: Pre-flight
- [ ] VLAN 3 trunked to host port. Run `tart run --net-bridged=list` on the host and record the **exact** VLAN-3 interface token (create the macOS VLAN interface if absent). This token feeds `VLAN_IFACE` (Task 9) and both run/checkpoint plists.
- [ ] **DHCP pool excludes `10.1.3.10`** (not just a reservation — the guest is static); confirm `.10` is unused (ping/arping) before Task 9.
- [ ] New SAN cert (apex + wildcard) generated and placed at `~/.foscs/fosshowcase/ssl/`; `~/.foscs/fosshowcase/.env` populated (mode 600).
- [ ] Firewall rules staged (egress pinhole, management pinhole) — WAN port-forward left OFF for now.
- [ ] Verify cert: `openssl x509 -in ~/.foscs/fosshowcase/ssl/foscomputerservices.com.crt -noout -ext subjectAltName` shows **both** apex and wildcard.

### Task 9: Provision VM
- [ ] On fos-openclaw: `VLAN_IFACE="<token from Task 8>" deploy/provision-vm.sh`.
- [ ] Install + load the run LaunchAgent (`com.foscs.tart-fos-showcase.plist`, with the real `--net-bridged` token) so the VM starts and stays up; run the in-guest provisioning block (netplan static `10.1.3.10`, Docker CE + compose plugin, NTP, SSH-key auth).
- [ ] Verify: from the VM, `ip a` shows `10.1.3.10`; `ping -c1 10.1.3.1` succeeds (ARPs gateway); `timedatectl` shows synced clock; `docker compose version` prints v2; `df -h /` shows the full ~32 GB (run `growpart`/`resize2fs` if the rootfs didn't auto-expand).

### Task 10: pg_hba + deploy + internal validation
- [ ] Apply live `pg_hba` `/32` + `pg_reload_conf()`; enable the egress pinhole.
- [ ] From dev Mac: `deploy/deploy.sh`; `docker compose ps` shows all three healthy.
- [ ] Verify (internal, against `10.1.3.10` directly, no WAN): website loads; server logs show a successful **direct** DB connect (not tunnel); a signed `/webhooks/` POST INSERTs a row visible via `webhook_read_alerts`.
- [ ] Isolation tests (authoritative test is cross-host):
  - Positive: from the VM, `nc -vz 10.1.2.158 5432` succeeds.
  - Negative (host-scope, authoritative): from the VM, a connection to a **different** internal host on any port is refused/filtered (proves the egress rule is host+port-scoped, not just relying on a service not listening).
  - Negative (port-scope, secondary): `nc -vz 10.1.2.158 3300` is refused. ⚠️ Treat as weak evidence — if fos-db MCP binds loopback-only this is refused regardless of the firewall. Confirm 3300 actually listens on `10.1.2.158`'s LAN interface before relying on it; otherwise lean on the cross-host test.

### Task 11: WAN cutover + external validation
- [ ] Enable WAN port-forward `80,443` → `10.1.3.10` + WAN→Web Servers allow.
- [ ] Verify externally: `openssl s_client` clean for apex and subdomain; a real TradingView test alert lands in `tv_alerts`; HTTP→HTTPS redirect works.

### Task 12: Post-cutover
- [ ] Install + load the checkpoint LaunchAgent on fos-openclaw; confirm one manual run produces a `fos-showcase-checkpoint-*` clone.
- [ ] Land the openclaw-config SYSTEM-MAP + pg_hba commits (merge branch).
- [ ] Monitor host load and the webhook path for 24h.

---

## Execution order

Phase 1 tasks 1–7 are independent of live infra and can be done/committed first (tasks 5–6 in openclaw-config). Phase 2 tasks 8→9→10→11→12 are strictly sequential.
