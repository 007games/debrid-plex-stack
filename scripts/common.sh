#!/bin/bash
# Shared settings and helpers. Sourced by the other scripts.

STACK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MNT="$STACK_DIR/mnt/zurg"
LOG="$STACK_DIR/logs/debrid.log"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
DOCKER=$(command -v docker)

envval() { sed -n "s/^$1=//p" "$STACK_DIR/.env" 2>/dev/null | tail -1; }

log() {
  mkdir -p "$(dirname "$LOG")"
  if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG")" -gt 1048576 ]; then
    mv -f "$LOG" "$LOG.1"
  fi
  echo "$(date '+%F %T') [$(basename "$0")] $*" >>"$LOG"
}

# COMPOSE_FILE in .env decides whether compose.gpu.yml is included
compose() { (cd "$STACK_DIR" && "$DOCKER" compose "$@"); }

container_running() {
  [ "$("$DOCKER" inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]
}

# Mounted AND answering (a stale FUSE mount errors or hangs on ls)
mount_ok() {
  grep -q " $MNT fuse.rclone " /proc/mounts && timeout 20 ls "$MNT/__all__" >/dev/null 2>&1
}

# Zurg answers on loopback (401 without credentials still means it's alive)
zurg_ok() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:9999/dav/)
  [ "$code" = "200" ] || [ "$code" = "207" ] || [ "$code" = "401" ]
}

unmount_stale() {
  if grep -q " $MNT " /proc/mounts; then
    fusermount -uz "$MNT" 2>/dev/null || fusermount3 -uz "$MNT" 2>/dev/null || umount -l "$MNT" 2>/dev/null
  fi
}

# rclone's rshared / plex's rslave binds need ./mnt on a shared mount.
# Make ./mnt its own shared bind mount, so nothing else on the host changes.
ensure_shared_mnt() {
  if ! awk -v m="$STACK_DIR/mnt" '$5 == m {f=1} END {exit !f}' /proc/self/mountinfo; then
    mount --bind "$STACK_DIR/mnt" "$STACK_DIR/mnt"
  fi
  mount --make-shared "$STACK_DIR/mnt"
}

mnt_is_shared() {
  awk -v m="$STACK_DIR/mnt" '$5 == m && / shared:/ {f=1} END {exit !f}' /proc/self/mountinfo
}

# Docker-published ports bypass host firewalls, so filter 32400 in DOCKER-USER:
# drop anything to Plex arriving on the LAN interface from outside the LAN subnet.
firewall_rule() {
  echo "-i $(envval LAN_IFACE) -p tcp --dport 32400 ! -s $(envval LAN_SUBNET) -j DROP"
}

ensure_firewall() {
  iptables -L DOCKER-USER -n >/dev/null 2>&1 || { log "firewall: DOCKER-USER chain not present yet"; return 1; }
  # shellcheck disable=SC2046
  if ! iptables -C DOCKER-USER $(firewall_rule) 2>/dev/null; then
    iptables -I DOCKER-USER 1 $(firewall_rule) && log "firewall: added DOCKER-USER rule ($(firewall_rule))"
  fi
}

# Resident memory of dockerd in MB
dockerd_rss_mb() {
  local p
  for p in /proc/[0-9]*; do
    case "$(tr '\0' ' ' <"$p/cmdline" 2>/dev/null)" in
      */dockerd*) awk '/^VmRSS/ {print int($2/1024)}' "$p/status"; return ;;
    esac
  done
}
