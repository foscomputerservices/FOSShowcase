#!/bin/bash
set -euo pipefail

# Remove a stale PostgreSQL postmaster.pid left behind by an unclean host
# shutdown, so the Homebrew launchd service can start on the next retry.
#
# Why: on 2026-10-06 a macOS upgrade reboot killed postgres mid "smart
# shutdown". After reboot the PID recorded in postmaster.pid belonged to an
# unrelated Apple XPC service, so postgres refused to start ("lock file
# already exists") every 10 s until the file was removed by hand. The
# showcase server container crash-looped on "connection refused" meanwhile.
#
# Safe by construction: the file is only moved aside when
#   1. no process with that PID exists, OR the process is not postgres, AND
#   2. nothing is listening on the cluster's port.
# The file is renamed, not deleted, so it can be inspected afterwards.
#
# Installed on fos-openclaw as ~/.foscs/scripts/postgres-clear-stale-lock.sh,
# run by ~/Library/LaunchAgents/com.foscs.postgres-stale-lock.plist.

PGDATA="${PGDATA:-/opt/homebrew/var/postgresql@18}"
PIDFILE="$PGDATA/postmaster.pid"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

[ -f "$PIDFILE" ] || exit 0

PID="$(sed -n 1p "$PIDFILE" | tr -d '[:space:]')"
PORT="$(sed -n 4p "$PIDFILE" | tr -d '[:space:]')"
PORT="${PORT:-5432}"

if [[ "$PID" =~ ^[0-9]+$ ]] && ps -p "$PID" -o comm= 2>/dev/null | grep -q 'postgres'; then
    exit 0   # live postmaster owns the lock
fi

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    log "postmaster.pid PID $PID is not postgres but port $PORT is in use; leaving the file alone"
    exit 0
fi

STALE="$PIDFILE.stale-$(date '+%Y%m%d-%H%M%S')"
mv "$PIDFILE" "$STALE"
log "moved stale postmaster.pid (PID $PID not a running postgres) to $STALE; launchd will retry postgres"
