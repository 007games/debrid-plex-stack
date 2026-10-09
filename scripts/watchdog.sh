#!/bin/bash
# Runs every 5 minutes. Heals a dead/stale mount, re-applies the firewall rule and
# logs runaway dockerd memory. Pause it with: touch <stack>/MAINTENANCE
. "$(dirname "$0")/common.sh"

exec 9>/tmp/debrid-watchdog.lock
flock -n 9 || exit 0

FAILS=/tmp/debrid-watchdog.fails

[ -f "$STACK_DIR/MAINTENANCE" ] && exit 0
"$DOCKER" inspect plex >/dev/null 2>&1 || exit 0   # stack deliberately down

ensure_firewall

dmem=$(dockerd_rss_mb)
if [ "${dmem:-0}" -gt 2048 ]; then
  log "warning: dockerd using ${dmem} MB RAM; top containers: $("$DOCKER" stats --no-stream --format '{{.Name}}={{.MemUsage}}' 2>/dev/null | sort -t= -k2 -h -r | head -3 | tr '\n' ' ')"
fi

if all_running && mount_ok; then
  rm -f "$FAILS"
  exit 0
fi

n=$(( $(cat "$FAILS" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$FAILS"
if [ "$n" -lt 2 ]; then
  log "watchdog: unhealthy (strike $n), checking again next run"
  exit 0
fi

log "watchdog: unhealthy twice in a row, recovering"
compose stop plex "$MOUNTER" >>"$LOG" 2>&1
unmount_stale
ensure_shared_mnt
if ! zurg_ok; then
  log "watchdog: zurg not answering, restarting it"
  compose restart zurg >>"$LOG" 2>&1
fi
compose up -d >>"$LOG" 2>&1

for _ in $(seq 24); do
  if mount_ok && container_running plex; then
    log "watchdog: recovered"
    rm -f "$FAILS"
    exit 0
  fi
  sleep 5
done
log "watchdog: still unhealthy after recovery attempt (will retry next run)"
