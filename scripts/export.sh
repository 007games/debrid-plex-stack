#!/bin/bash
# Pack this install's settings for moving to another machine.
#   sudo bash scripts/export.sh [DEST_DIR]      (default: your home folder)
#
# Included: Plex database and settings (library, watch history, claim), the management
#           page password, and .env / zurg / rclone config for reference.
# Left out: the cloud mount, caches, logs, Plex's cache/codecs/GPU drivers (machine-
#           specific; Plex downloads them again), and all code (that comes
#           from GitHub on the new machine).
# The archive contains secrets (API key, Plex token): keep it private, delete it after the move.
. "$(dirname "$0")/common.sh"
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }

dest=${1:-}
if [ -z "$dest" ]; then
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then dest=$(eval echo "~$SUDO_USER"); else dest=/root; fi
fi
[ -d "$dest" ] || { echo "no such folder: $dest"; exit 1; }
out="$dest/debrid-export-$(date +%F-%H%M).tar.gz"

items=()
for p in .env zurg/config.yml rclone/rclone.conf plex/config admin/auth/password.hash; do
  [ -e "$STACK_DIR/$p" ] && items+=("$p")
done

# Plex's database must not change while it's copied. Pause the watchdog first, or it
# sees Plex down and restarts it halfway through the copy.
paused_here=no
[ -f "$STACK_DIR/MAINTENANCE" ] || { touch "$STACK_DIR/MAINTENANCE"; paused_here=yes; }
trap '[ "$paused_here" = yes ] && rm -f "$STACK_DIR/MAINTENANCE"' EXIT
was_running=no
container_running plex && { was_running=yes; echo "Stopping Plex for a consistent copy..."; compose stop plex >/dev/null 2>&1; }

PMS="plex/config/Library/Application Support/Plex Media Server"
umask 077
tar -czf "$out" -C "$STACK_DIR" \
  --exclude="$PMS/Cache" --exclude="$PMS/Codecs" --exclude="$PMS/Drivers" --exclude="$PMS/Logs" \
  --exclude="$PMS/Crash Reports" --exclude="$PMS/Diagnostics" --exclude="$PMS/Updates" \
  --exclude="*.bak-*" \
  "${items[@]}"
rc=$?

[ "$was_running" = yes ] && [ ! -f "$STACK_DIR/STOPPED" ] && compose start plex >/dev/null 2>&1
[ $rc -eq 0 ] || { rm -f "$out"; echo "export failed"; exit 1; }

[ -n "${SUDO_USER:-}" ] && chown "$SUDO_USER" "$out"
chmod 600 "$out"
log "export: wrote $out"
echo "Exported $(du -h "$out" | cut -f1) to $out"
echo "It contains secrets: copy it to the new machine privately and delete it afterwards."
