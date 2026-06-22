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
