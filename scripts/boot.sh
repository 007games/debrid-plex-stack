#!/bin/bash
# Run at boot (systemd unit or Synology boot task) and by install.sh.
. "$(dirname "$0")/common.sh"

log "boot: start"
ensure_shared_mnt && log "boot: mnt is a shared mount"
unmount_stale

for _ in $(seq 60); do
  "$DOCKER" info >/dev/null 2>&1 && break
  sleep 5
done

ensure_firewall
compose up -d >>"$LOG" 2>&1 && log "boot: stack up" || log "boot: compose up FAILED"
