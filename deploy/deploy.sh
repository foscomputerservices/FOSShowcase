#!/bin/bash
set -euo pipefail

# Deliver secrets/certs/repo to the fos-showcase VM and (re)deploy the stack.
# Run from the dev Mac (local LAN — allowed by the management firewall pinhole).

VM_HOST="${VM_HOST:-admin@10.1.3.10}"
VM_PATH="${VM_PATH:-/opt/fosshowcase}"
SRC_SECRETS="${SRC_SECRETS:-$HOME/.foscs/fosshowcase}"   # canonical .env + ssl/ source
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
SSH_CMD="ssh -o StrictHostKeyChecking=accept-new"

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
  -e "$SSH_CMD" \
  "$REPO_ROOT/" "$VM_HOST:$VM_PATH/"

echo "==> Delivering secrets + certs (mode 600)"
rsync -az -e "$SSH_CMD" "$SRC_SECRETS/.env" "$VM_HOST:$VM_PATH/.env"
rsync -az -e "$SSH_CMD" "$SRC_SECRETS/ssl/" "$VM_HOST:$VM_PATH/ssl/"
ssh "${SSH_OPTS[@]}" "$VM_HOST" "chmod 600 $VM_PATH/.env && chmod 600 $VM_PATH/ssl/*.key"

echo "==> Building + starting stack"
ssh "${SSH_OPTS[@]}" "$VM_HOST" "cd '$VM_PATH' && docker compose up -d --build"

echo "==> Container status"
ssh "${SSH_OPTS[@]}" "$VM_HOST" "cd '$VM_PATH' && docker compose ps"
