#!/bin/bash
# Stop the whole stack and keep it stopped: the watchdog and the boot task leave it
# alone until scripts/start.sh. Plex, zurg, rclone and the management page stop.
#   sudo bash scripts/stop.sh
# (Synology: create a Task Scheduler task for this and start it with "Run".)
. "$(dirname "$0")/common.sh"
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }

touch "$STACK_DIR/STOPPED"
compose stop >>"$LOG" 2>&1
unmount_stale
log "stop: stack stopped on purpose (start again with scripts/start.sh)"
echo "Stack stopped. It stays stopped (also after a reboot) until: sudo bash $STACK_DIR/scripts/start.sh"
