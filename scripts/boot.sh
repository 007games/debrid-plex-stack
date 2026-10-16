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
if [ -f "$STACK_DIR/STOPPED" ]; then
  log "boot: stack was stopped with scripts/stop.sh, not starting it (run scripts/start.sh)"
  exit 0
fi
compose up -d >>"$LOG" 2>&1 && log "boot: stack up" || log "boot: compose up FAILED"
