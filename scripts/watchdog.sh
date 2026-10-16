#!/bin/bash
# Runs every minute. Heals a dead/stale mount (after two failed checks), re-applies the
# firewall rules, logs runaway dockerd memory and runs the management-page agent.
# Pause healing with: touch <stack>/MAINTENANCE
. "$(dirname "$0")/common.sh"

# Lock held by a separate flock process (-o), so long-running children never inherit it
if [ -z "${DEBRID_WD_LOCKED:-}" ]; then
  DEBRID_WD_LOCKED=1 exec flock -n -o /tmp/debrid-watchdog.v2.lock bash "$0" "$@"
fi

FAILS=/tmp/debrid-watchdog.fails

# Management page requests + status (also during maintenance, so it can be switched off)
[ -d "$STACK_DIR/admin/requests" ] && bash "$(dirname "$0")/agent.sh"

# For the rest of this minute, look in the page's inbox every 3 seconds and run the
# agent only when a request is waiting (one poller at a time; never holds our lock)
if [ -d "$STACK_DIR/admin/requests" ]; then
  flock -n -o /tmp/debrid-poll.lock bash -c '
    for _ in $(seq 18); do
      sleep 3
      ls "$1"/admin/requests/*.req >/dev/null 2>&1 && bash "$1"/scripts/agent.sh
    done' _ "$STACK_DIR" >/dev/null 2>&1 &
fi

[ -f "$STACK_DIR/STOPPED" ] && exit 0       # stopped on purpose with scripts/stop.sh
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
