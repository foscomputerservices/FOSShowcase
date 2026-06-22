# Runbook: Pi → VM Cutover (FOSShowcase)

**Branch:** `migration/pi-to-vm`
**Date:** 2026-06-22
**Spec:** `docs/superpowers/specs/2026-06-22-pi-to-vm-migration-design.md`
**Plan:** `docs/superpowers/plans/2026-06-22-pi-to-vm-migration.md`

## Summary

Move the FOSShowcase Docker Compose stack (nginx/client/server) off the decommissioned Raspberry Pi
onto an isolated Tart Linux VM on fos-openclaw (`10.1.2.158`). The VM sits on VLAN 3 "Public Servers"
(`10.1.3.10`), connects directly to the `foscs` Postgres database (no SSH tunnel), and is exposed
publicly on ports 80/443 only.

**There is no Pi fallback.** The Pi is gone. Do not flip the WAN port-forward until internal
validation on `10.1.3.10` passes in full.

### Quick-reference: key values

| Item | Value |
|---|---|
| Tart host | fos-openclaw, `10.1.2.158` (Apple Silicon Mac Mini) |
| VM name | `fos-showcase` |
| VM OS | Ubuntu 24.04 (noble) arm64 |
| VM IP | `10.1.3.10/24`, gateway `10.1.3.1` |
| VLAN | 3 "Public Servers", UDM Pro zone "Web Servers" (Isolate Network = on) |
| DHCP pool | `10.1.3.6–254` — EXCLUDE `.10` (VM is static; reservation is not enough) |
| Database | `foscs` on `10.1.2.158:5432` |
| DB runtime role | `openclaw_webhook` |
| DB migration role | `openclaw_admin` |
| psql binary | `/opt/homebrew/Cellar/postgresql@18/18.2/bin/psql` |
| Cert filenames | `foscomputerservices.com.crt` / `foscomputerservices.com.key` (hardcoded in nginx.conf) |
| Canonical secrets/certs | `~/.foscs/fosshowcase/{.env,ssl/}` on the dev Mac (mode 600) |
| VM repo path | `/opt/fosshowcase` |
| VM admin user | `admin` |

---

## Section 1: Infra Prerequisites (UDM Pro)

### 1a. VLAN 3 trunk to the host switch port

VLAN 20 is already trunked to fos-openclaw's switch port (proven by `openclaw-vm`). VLAN 3 is
**not** confirmed. Trunk it before provisioning — if the VM can't ARP `10.1.3.1`, it has no network
and all subsequent steps fail silently.

**UDM Pro steps:**
1. In the UniFi Network UI, go to Settings → Networks and verify "Public Servers" exists as VLAN 3.
2. Go to Devices → fos-openclaw's switch → Port configuration. Ensure the port profile includes
   VLAN 3 as a tagged (trunk) VLAN.
3. Apply and wait for the switch to update.

**Discover the VLAN-3 interface token on fos-openclaw** (run this on the host, not in the VM):

```bash
# On fos-openclaw:
tart run --net-bridged=list
```

Look for an interface tagged with VLAN 3. If it does not appear, create a macOS VLAN interface:

```bash
# On fos-openclaw — create a VLAN 3 interface on the NIC (replace en0 with the actual NIC name):
# Find the real NIC: networksetup -listallhardwareports
sudo networksetup -createVLAN "VLAN3-PublicServers" en0 3
# Verify it appears:
tart run --net-bridged=list
```

Record the **exact** token (it may look like `en0.3` or the VLAN service name). You will use this
value in every subsequent command that references `VLAN_IFACE`.

```bash
# Set it for the rest of this session:
export VLAN_IFACE="<TOKEN_FROM_ABOVE>"   # e.g. en0.3
```

### 1b. DHCP pool exclusion for 10.1.3.10

The VM uses a **static** netplan address (`10.1.3.10`). A DHCP reservation is not sufficient —
another device could receive `.10` before the reservation kicks in. You must exclude `.10` from the
pool.

**UDM Pro steps:**
1. Go to Settings → Networks → "Public Servers" (VLAN 3).
2. Change the DHCP start address from `10.1.3.6` to `10.1.3.11` (shrinking the pool so `.10` is
   never leased).
   — **or** — configure a static IP exclusion for `10.1.3.10` if your UDM Pro firmware supports it.
3. Apply.

**Confirm `.10` is free before bringing up the VM:**

```bash
# From any host on the VLAN-3 segment or from the UDM Pro:
ping -c 3 10.1.3.10    # must be 100% packet loss
arping -c 3 10.1.3.10  # must show "no reply"
```

If either responds, find and shut down whatever owns that address before proceeding.

### 1c. SAN cert generation

The current cert is wildcard-only (`*.foscomputerservices.com`); it does **not** cover the apex
`foscomputerservices.com`. Reissue a SAN cert covering **both** the apex and the wildcard. The cert
expires 2026-07-20 — reissue now.

**Required filenames (hardcoded in nginx.conf — do not rename):**
- `foscomputerservices.com.crt`
- `foscomputerservices.com.key`

**Generate with Let's Encrypt (certbot DNS challenge, run on the dev Mac or any internet-connected
host):**

```bash
# Replace YOUR_EMAIL with your actual email:
certbot certonly \
  --manual \
  --preferred-challenges dns \
  -d foscomputerservices.com \
  -d '*.foscomputerservices.com' \
  --agree-tos \
  -m YOUR_EMAIL

# After issuance, copy to the canonical location with the exact required names:
mkdir -p ~/.foscs/fosshowcase/ssl
cp /etc/letsencrypt/live/foscomputerservices.com/fullchain.pem \
   ~/.foscs/fosshowcase/ssl/foscomputerservices.com.crt
cp /etc/letsencrypt/live/foscomputerservices.com/privkey.pem \
   ~/.foscs/fosshowcase/ssl/foscomputerservices.com.key
chmod 600 ~/.foscs/fosshowcase/ssl/foscomputerservices.com.key
```

**Verify the SAN before proceeding (both entries must appear):**

```bash
openssl x509 \
  -in ~/.foscs/fosshowcase/ssl/foscomputerservices.com.crt \
  -noout -ext subjectAltName
# Expected output must include both:
#   DNS:foscomputerservices.com
#   DNS:*.foscomputerservices.com
```

---

## Section 2: Firewall Rules (Web Servers Zone — Exactly Three Holes)

Configure these in the UDM Pro before deploying, but **leave the WAN port-forward OFF** until
internal validation (Section 5) passes.

### Hole 1: Egress — VM to PostgreSQL only

Allow the VM to reach the database and nothing else internally.

**UDM Pro: Settings → Firewall & Security → Rules → LAN**

Create a rule in the "Web Servers" zone (or as a traffic rule from VLAN 3):

| Field | Value |
|---|---|
| Action | Accept |
| Source | `10.1.3.10/32` |
| Destination | `10.1.2.158`, port `5432`, protocol TCP |
| Description | `fos-showcase → foscs PostgreSQL` |

Then add a default-deny rule for all other VM egress to internal zones (VLAN 3's "Isolate Network"
setting handles this, but explicitly confirm that inter-VLAN traffic from `10.1.3.0/24` is blocked
by default. If you have a catch-all LAN→LAN block rule, the accept rule above must be ordered
**above** it).

### Hole 2: Ingress — WAN 80/443 only (NO 8081)

This is a two-part configuration: a port-forward and a firewall allow.

**Stage the port-forward — but do NOT enable it yet:**

| Field | Value |
|---|---|
| Enabled | OFF (enable only after internal validation) |
| Protocol | TCP |
| WAN port(s) | 80, 443 |
| Forward IP | `10.1.3.10` |
| Forward port(s) | 80, 443 |
| Description | `FOSShowcase public ingress` |

**Firewall allow (WAN → Web Servers zone):**

| Field | Value |
|---|---|
| Action | Accept |
| Source | WAN / any |
| Destination | `10.1.3.10`, ports `80, 443` |
| Description | `WAN → fos-showcase HTTP/HTTPS` |

Port 8081 is deliberately excluded. The 8081 listener runs inside the VM (reachable on the VLAN)
but is not forwarded to the internet — the native-app backend API is out of scope for this migration.

### Hole 3: Management — Local LAN(s) to VM SSH only

Allow SSH from your administrative LAN(s) to the VM. **Never expose port 22 to the WAN.**

| Field | Value |
|---|---|
| Action | Accept |
| Source | Local LAN CIDR(s) (e.g. `10.1.2.0/24`, `10.1.20.0/24`) |
| Destination | `10.1.3.10`, port `22`, protocol TCP |
| Description | `Local LAN → fos-showcase SSH management` |

---

## Section 3: In-Guest Provisioning

### 3a. First-boot access

After Tart clones and starts the VM with bridged networking (`--net-bridged=$VLAN_IFACE`), the VM
boots with a default Ubuntu 24.04 image. Find its initial IP (DHCP, not yet static) from the Tart
console or the UDM Pro DHCP leases, then SSH in:

```bash
# Default credentials for the ghcr.io/cirruslabs/ubuntu:24.04 image:
# user: admin  password: admin
ssh admin@<INITIAL_DHCP_IP>
```

Once you're in, run the following provisioning block. The commands are ordered and can be pasted as
one block into the SSH session.

### 3b. In-guest provisioning commands (copy-paste block)

```bash
# ============================================================
# FOSShowcase VM in-guest provisioning
# Run as: admin@<initial-dhcp-ip>
# ============================================================

# --- 1. Static network (netplan) ---
# Discover the primary NIC name (Tart Ubuntu guests are often enp0s1, not eth0):
IFACE=$(ip -o link show | awk -F': ' '$2 != "lo"{print $2; exit}')
echo "Primary interface: $IFACE"   # substitute this name in the netplan below

# Replace <IFACE> in the heredoc with the value printed above before applying:
sudo tee /etc/netplan/01-static.yaml > /dev/null <<NETPLAN
network:
  version: 2
  ethernets:
    $IFACE:
      dhcp4: false
      addresses:
        - 10.1.3.10/24
      routes:
        - to: default
          via: 10.1.3.1
      nameservers:
        addresses:
          - 10.1.3.1
          - 1.1.1.1
NETPLAN

# Disable the DHCP config that ships with the base image:
sudo rm -f /etc/netplan/00-installer-config.yaml /etc/netplan/50-cloud-init.yaml 2>/dev/null || true

sudo netplan apply
# After this, your SSH session may drop. Reconnect on 10.1.3.10:
# ssh admin@10.1.3.10

# --- 2. NTP (clock-sensitive: HMAC signatures + TLS certificates) ---
sudo systemctl enable --now systemd-timesyncd
timedatectl set-ntp true
timedatectl status    # confirm: "System clock synchronized: yes"

# --- 3. Docker CE + docker-compose-plugin (official repo, arm64) ---
# Ubuntu's docker.io package does NOT ship docker compose v2 — use Docker's own repo.
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# Add admin user to the docker group (no sudo needed for docker commands):
sudo usermod -aG docker admin
newgrp docker   # applies in this session; new sessions pick it up automatically

# Verify:
docker compose version   # must print v2.x

# --- 4. Disk expansion (if rootfs didn't auto-expand to the full 32 GB) ---
df -h /
# If /dev/sda or /dev/vda shows < 30 GB, expand it:
# (adjust /dev/sda1 to the actual root partition from 'lsblk')
sudo apt-get install -y cloud-guest-utils
sudo growpart /dev/sda 1
sudo resize2fs /dev/sda1
df -h /   # should now show ~30 GB

# --- 5. SSH hardening ---
# Install your public key:
mkdir -p ~/.ssh && chmod 700 ~/.ssh
# Paste your public key (from the dev Mac: cat ~/.ssh/id_ed25519.pub or similar):
echo "PASTE_YOUR_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Disable password authentication:
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
  /etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' \
  /etc/ssh/sshd_config
sudo systemctl reload sshd

# Verify SSH key auth before closing this session:
# Open a second terminal: ssh admin@10.1.3.10
# Confirm it logs in without a password prompt, then close this window.

# --- 6. Create repo directory ---
sudo mkdir -p /opt/fosshowcase
sudo chown admin:admin /opt/fosshowcase

echo "=== In-guest provisioning complete ==="
echo "Reconnect via: ssh admin@10.1.3.10"
```

### 3c. Post-provisioning checks (run from the VM)

```bash
# Run these from inside the VM after reconnecting on 10.1.3.10:

# Network identity:
ip a show <IFACE>       # must show 10.1.3.10/24 (replace <IFACE> with the discovered NIC name, e.g. enp0s1)
ping -c 2 10.1.3.1     # gateway reachable (ARP works)
ping -c 2 1.1.1.1      # internet reachable

# Clock:
timedatectl | grep -E "synchronized|NTP"

# Docker:
docker compose version  # must print v2.x

# Disk:
df -h /                 # must show ~30 GB available
```

### 3d. Install the VM run LaunchAgent on fos-openclaw (host)

The VM must start automatically and stay up across host reboots. The LaunchAgent lives in this repo
at `deploy/com.foscs.tart-fos-showcase.plist`. Before installing it, substitute the real VLAN-3
interface token you discovered in Section 1a.

```bash
# On fos-openclaw (run from the dev Mac via SSH, or directly on the host):

# 1. Edit the plist to insert the real interface token:
#    Replace REPLACE_WITH_VLAN3_INTERFACE with $VLAN_IFACE (e.g. en0.3)
#    in deploy/com.foscs.tart-fos-showcase.plist (already cloned here)

# 2. Copy to LaunchAgents:
cp /path/to/FOSShowcase/deploy/com.foscs.tart-fos-showcase.plist \
   ~/Library/LaunchAgents/

# 3. Load (starts immediately and survives reboots):
launchctl load ~/Library/LaunchAgents/com.foscs.tart-fos-showcase.plist

# 4. Confirm the VM is running:
tart list | grep fos-showcase    # shows "running"
```

---

## Section 4: Live pg_hba Apply (No Restart)

The production `foscs` database on fos-openclaw must accept connections from `10.1.3.10`. Do this
with a **reload** — not a restart, and do **not** run `setup-postgres.sh` on the production database
(its step 4 does `brew services restart postgresql@18`, which bounces production).

```bash
# On fos-openclaw (the database host):
PG_HBA="$(psql_bin -U postgres -t -c "SHOW hba_file;" | tr -d ' ')"
# Or find it manually — typically:
# /opt/homebrew/var/postgresql@18/pg_hba.conf

# Use the full psql path (not in PATH by default):
PSQL=/opt/homebrew/Cellar/postgresql@18/18.2/bin/psql

# 1. Confirm the line isn't already there:
grep "10.1.3.10" /opt/homebrew/var/postgresql@18/pg_hba.conf || true

# 2. Append the new /32 grant:
echo "host    foscs    all    10.1.3.10/32    scram-sha-256" \
  >> /opt/homebrew/var/postgresql@18/pg_hba.conf

# 3. Reload (NOT restart) — applies immediately, zero downtime:
$PSQL -U postgres -c "SELECT pg_reload_conf();"
# Expected output: pg_reload_conf
#                 ----------------
#                  t

# 4. Verify it was accepted:
$PSQL -U postgres -c "SELECT type, database, user_name, address, auth_method FROM pg_hba_file_rules WHERE address = '10.1.3.10/32';"
# Must show one row for foscs / scram-sha-256
```

---

## Section 5: Cutover Sequence

Execute in strict order. **Do not advance to the next step if the current one fails.**

```
Step 1: Infra prerequisites (Section 1)
   ├── VLAN 3 trunked → host switch port
   ├── DHCP pool excludes 10.1.3.10
   └── SAN cert generated, filenames correct, at ~/.foscs/fosshowcase/ssl/

Step 2: Firewall staged (Section 2)
   ├── Egress pinhole: 10.1.3.10 → 10.1.2.158:5432 TCP
   ├── Management: local LAN(s) → 10.1.3.10:22
   └── WAN port-forward: STAGED BUT DISABLED

Step 3: VM provisioned (Sections 3a–3c)
   ├── tart run fos-showcase --net-bridged=$VLAN_IFACE --no-graphics
   ├── In-guest block run (netplan, Docker, NTP, SSH hardening)
   ├── VM answers on 10.1.3.10, clock synced, docker compose v2 available
   └── Run LaunchAgent installed on host (Section 3d)

Step 4: pg_hba applied (Section 4)
   ├── 10.1.3.10/32 line appended to pg_hba.conf
   └── pg_reload_conf() returned t

Step 5: Deploy (from dev Mac)
   └── ./deploy/deploy.sh
       # Syncs repo + .env + ssl/ to 10.1.3.10, runs docker compose up -d --build

Step 6: Internal validation ← GATE: do not advance until ALL pass
   └── See Section 6 (internal checks only, against 10.1.3.10 directly)

Step 7: Enable WAN port-forward (UDM Pro)
   └── Set port-forward 80/443 → 10.1.3.10 to ENABLED

Step 8: External validation
   └── See Section 6 (external checks)

Step 9: Post-cutover
   └── Section 7 (checkpoint LaunchAgent) + SYSTEM-MAP update
```

### Step 5 expanded: running deploy.sh

```bash
# From the dev Mac:
cd /path/to/FOSShowcase
./deploy/deploy.sh

# Expected output ends with all three containers Up:
# NAME           IMAGE                    STATUS
# nginx          ...                      Up X seconds
# client         ...                      Up X seconds
# server         ...                      Up X seconds
```

If the build fails (Swift compiler OOM), the 6 GB VM sizing should prevent this, but if it happens:
check `docker stats` on the VM and confirm no other heavy process is competing.

---

## Section 6: Verification

Run the internal checks (Steps I1–I4) **before** flipping the WAN port-forward. Run external checks
(Steps E1–E3) after.

### Internal verification (against 10.1.3.10 directly)

**I1. Stack health:**

```bash
# From dev Mac:
ssh admin@10.1.3.10 "cd /opt/fosshowcase && docker compose ps"
# All three containers must show State=Up (not Restarting, not Exit)
```

**I2. TLS — website loads, cert is correct:**

```bash
# From dev Mac (via management SSH):
# Use openssl, NOT curl — curl can silently tolerate bad TLS.
openssl s_client \
  -connect 10.1.3.10:443 \
  -servername foscomputerservices.com \
  </dev/null 2>&1 | head -30
# Look for:
#   subject=CN=foscomputerservices.com (or similar)
#   issuer=...
#   Verify return code: 0 (ok)  ← critical; any other code = cert problem
```

Check both apex and wildcard SAN by varying -servername:

```bash
openssl s_client -connect 10.1.3.10:443 -servername foscomputerservices.com </dev/null 2>&1 | \
  grep -E "subject|Verify return"

openssl s_client -connect 10.1.3.10:443 -servername www.foscomputerservices.com </dev/null 2>&1 | \
  grep -E "subject|Verify return"
```

**I3. DB connection (direct, no tunnel):**

```bash
# From inside the VM:
ssh admin@10.1.3.10
docker compose -f /opt/fosshowcase/docker-compose.yml logs server | grep -i "database\|connect\|error" | tail -20
# Expect a successful direct connection to 10.1.2.158:5432 — NOT via host-gateway or tunnel.
# "Connection established" or equivalent from the Vapor startup.
```

**I4. Webhook round-trip (simulated POST):**

```bash
# From dev Mac — replace WEBHOOK_SECRET with the value from ~/.foscs/fosshowcase/.env:
WEBHOOK_SECRET="<your-webhook-secret>"
PAYLOAD='{"ticker":"TEST","action":"buy","price":100}'
SIG=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" -hex | awk '{print $2}')

curl -sk -X POST \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Signature: $SIG" \
  -d "$PAYLOAD" \
  https://10.1.3.10/webhooks/ \
  --resolve foscomputerservices.com:443:10.1.3.10
# Expected: HTTP 200 or 204 (server accepted the alert)
```

Then confirm the row was inserted — use the `webhook_read_alerts` MCP tool or:

```bash
# On fos-openclaw (the DB host):
/opt/homebrew/Cellar/postgresql@18/18.2/bin/psql -U openclaw_webhook -d foscs \
  -c "SELECT * FROM webhook.tv_alerts ORDER BY created_at DESC LIMIT 3;"
# The TEST row must appear.
```

### Isolation tests

**Positive — VM can reach Postgres:**

```bash
# Inside the VM:
nc -vz 10.1.2.158 5432
# Must succeed: "Connection to 10.1.2.158 5432 port [tcp/postgresql] succeeded!"
```

**Negative (host-scope, authoritative) — VM cannot reach a different internal host:**

```bash
# Inside the VM — pick any internal host that is NOT 10.1.2.158:
# e.g. fos-dev at 10.1.2.201
nc -vz -w5 10.1.2.201 22
# Must FAIL: "Connection timed out" or "Connection refused"
# This proves the egress allow is host+port scoped, not host-wide.
```

**Negative (port-scope, secondary/weak) — VM refused to port 3300:**

```bash
# Inside the VM:
nc -vz -w5 10.1.2.158 3300
# Expected: refused or timed out
# NOTE: This is weak evidence if fos-db MCP binds loopback-only on 10.1.2.158
# (it would be refused regardless of the firewall). Lean on the cross-host test above.
# Confirm whether 3300 actually binds the LAN interface before treating this as a firewall proof:
# On fos-openclaw: sudo lsof -iTCP:3300 -sTCP:LISTEN
```

### External verification (after WAN port-forward is enabled)

**E1. TLS — apex and a subdomain via real DNS:**

```bash
# From ANY external host (not on the LAN), or use a phone on cellular:
openssl s_client \
  -connect foscomputerservices.com:443 \
  -servername foscomputerservices.com \
  </dev/null 2>&1 | grep -E "subject|SAN|Verify return"
# Verify return code: 0 (ok)

openssl s_client \
  -connect www.foscomputerservices.com:443 \
  -servername www.foscomputerservices.com \
  </dev/null 2>&1 | grep -E "subject|SAN|Verify return"
```

**E2. HTTP → HTTPS redirect:**

```bash
curl -I http://foscomputerservices.com/
# Expected: HTTP/1.1 301 Moved Permanently  Location: https://...
```

**E3. TradingView test alert (real webhook path):**

Send a test alert from TradingView pointing to `https://foscomputerservices.com/webhooks/`. Then
confirm it landed using the `webhook_read_alerts` MCP tool:

```
webhook_read_alerts(limit: 5)
```

The test ticker must appear as the most recent row.

---

## Section 7: Checkpoint LaunchAgent Install

The daily Tart checkpoint for `fos-showcase` runs at 02:30 (offset from `openclaw-vm`'s 02:00 to
avoid I/O collision). The plist lives in this repo at
`deploy/com.foscs.tart-fos-showcase-checkpoint.plist`. It calls the checkpoint script already
deployed by openclaw-config at `~/.foscs/scripts/tart-daily-checkpoint.sh` with `fos-showcase` as
the argument.

**This plist is NOT auto-deployed by openclaw-config's `deploy-all.sh`** — install it manually:

```bash
# On fos-openclaw (the Tart host):

# 1. Copy to LaunchAgents:
cp /path/to/FOSShowcase/deploy/com.foscs.tart-fos-showcase-checkpoint.plist \
   ~/Library/LaunchAgents/

# 2. Validate the plist:
plutil -lint ~/Library/LaunchAgents/com.foscs.tart-fos-showcase-checkpoint.plist
# Expected: OK

# 3. Load:
launchctl load ~/Library/LaunchAgents/com.foscs.tart-fos-showcase-checkpoint.plist

# 4. Confirm it loaded (will NOT run immediately; StartCalendarInterval fires at 02:30):
launchctl list | grep fos-showcase-checkpoint

# 5. Manual test run (optional but recommended — confirms the script works before the first
#    scheduled run):
/Users/david/.foscs/scripts/tart-daily-checkpoint.sh fos-showcase

# After the script completes, verify a checkpoint clone exists:
tart list | grep fos-showcase-checkpoint
# Expected: one entry like fos-showcase-checkpoint-20260622 (or similar date stamp)
```

**Retention:** the checkpoint script honours the `RETENTION_COUNT` environment variable (set to `7`
in the plist); it prunes checkpoints older than 7 days automatically.

---

## Section 8: Rollback

**There is no Pi fallback.** The Pi is decommissioned and unavailable.

The only rollback available is:

1. **Disable the WAN port-forward** (UDM Pro → port-forward for 80/443 → set Enabled = OFF).
   The site goes dark externally. Internal services (trading pipeline, DB) are unaffected — they
   read `webhook.tv_alerts` directly from the DB, not from FOSShowcase.

2. **Debug on the direct VM IP** (`10.1.3.10`). The management SSH hole (local LAN → :22) remains
   open. You can `docker compose logs`, `docker compose restart`, redeploy, or fix config and
   re-run `./deploy/deploy.sh` — all over the management channel.

3. **Re-enable the WAN port-forward** once the issue is resolved and internal validation passes
   again.

### Rollback decision tree

```
Site down externally after WAN flip?
├── TLS error → cert issue (wrong filename? SAN mismatch?)
│   └── Check: openssl x509 -in ~/.foscs/fosshowcase/ssl/foscomputerservices.com.crt -noout -ext subjectAltName
├── Connection refused / timeout → port-forward or firewall misconfiguration
│   └── Check: nc -vz <WAN_IP> 443  from external; confirm port-forward target IP
├── HTTP 502/503 → container down
│   └── Check: ssh admin@10.1.3.10 "docker compose ps && docker compose logs --tail 50"
├── DB connection error in server logs
│   └── Check pg_hba grant is present; check egress firewall rule; nc -vz 10.1.2.158 5432 from VM
└── Webhook POST fails → HMAC secret mismatch or env var missing
    └── Check .env on VM: ssh admin@10.1.3.10 "grep WEBHOOK_SECRET /opt/fosshowcase/.env"
```

---

## Appendix: Placeholder Reference

The following values must be substituted with your actual environment values before running commands:

| Placeholder | How to obtain |
|---|---|
| `<TOKEN_FROM_ABOVE>` / `$VLAN_IFACE` | `tart run --net-bridged=list` on fos-openclaw after trunking VLAN 3 |
| `<INITIAL_DHCP_IP>` | UDM Pro DHCP leases table, or `tart run` console output, immediately after VM boot |
| `PASTE_YOUR_PUBLIC_KEY_HERE` | `cat ~/.ssh/id_ed25519.pub` on the dev Mac (or whichever key you use for SSH) |
| `<your-webhook-secret>` | `grep WEBHOOK_SECRET ~/.foscs/fosshowcase/.env` |
| `YOUR_EMAIL` | Your email address for Let's Encrypt registration |
| `/path/to/FOSShowcase` | Absolute path where the FOSShowcase repo is checked out on fos-openclaw |
