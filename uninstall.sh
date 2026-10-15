#!/bin/bash
# Stops and removes the stack. Keeps your config and Plex library unless --purge.
#   sudo bash uninstall.sh [--purge]
. "$(dirname "$0")/scripts/common.sh"

[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }

touch "$STACK_DIR/MAINTENANCE"
compose down --remove-orphans
unmount_stale
umount "$STACK_DIR/mnt" 2>/dev/null
for port in $(firewall_ports); do
  # shellcheck disable=SC2046
  iptables -D DOCKER-USER $(firewall_rule "$port") 2>/dev/null
done

if command -v systemctl >/dev/null; then
  systemctl disable --now debrid-watchdog.timer debrid-boot.service debrid-agent.path 2>/dev/null
  rm -f /etc/systemd/system/debrid-{boot,watchdog,agent}.service /etc/systemd/system/debrid-watchdog.timer \
        /etc/systemd/system/debrid-agent.path
  systemctl daemon-reload
fi
[ -d /usr/syno ] && echo "Synology: also delete the two debrid tasks in Control Panel > Task Scheduler."

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$STACK_DIR"
  echo "Removed $STACK_DIR (your Real-Debrid account is untouched)."
else
  rm -f "$STACK_DIR/MAINTENANCE"
  echo "Stack removed. Config and Plex library kept in $STACK_DIR (use --purge to delete)."
fi
