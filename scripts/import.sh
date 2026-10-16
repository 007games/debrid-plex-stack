#!/bin/bash
# Restore an export from another machine, after install.sh has run here.
#   sudo bash scripts/import.sh /path/to/debrid-export-YYYY-MM-DD-HHMM.tar.gz
#
# Restores the Plex library, watch history and settings, and the management page
# password. This machine keeps its own .env, keys and certificate (they belong to this
# machine's IP and setup); the old ones are saved in import-reference/ for comparison.
# Stop the old machine's stack first (scripts/stop.sh there): both would otherwise
# announce the same Plex server.
. "$(dirname "$0")/common.sh"
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }

arc=${1:-}
[ -f "$arc" ] || { echo "usage: sudo bash scripts/import.sh debrid-export-....tar.gz"; exit 1; }

# Refuse archives with absolute paths, '..' or any symlink/hardlink (could point outside)
if tar -tzf "$arc" | grep -qE '(^/|(^|/)\.\.(/|$))'; then echo "unsafe paths in archive, aborting"; exit 1; fi
if tar -tvzf "$arc" | grep -qE '^[lh]'; then echo "archive contains links, aborting"; exit 1; fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tar -xzf "$arc" -C "$tmp" --no-same-owner || { echo "could not unpack $arc"; exit 1; }

stamp=$(date +%F-%H%M)
touch "$STACK_DIR/MAINTENANCE"
compose stop plex >/dev/null 2>&1

if [ -d "$tmp/plex/config" ]; then
  echo "Restoring the Plex library and settings..."
  [ -d "$STACK_DIR/plex/config" ] && mv "$STACK_DIR/plex/config" "$STACK_DIR/plex/config.before-import-$stamp"
  mv "$tmp/plex/config" "$STACK_DIR/plex/config"
  chown -R "$(envval PUID):$(envval PGID)" "$STACK_DIR/plex"
fi

if [ -f "$tmp/admin/auth/password.hash" ] && [ -d "$STACK_DIR/admin/auth" ]; then
  echo "Restoring the management page password..."
  mv -f "$tmp/admin/auth/password.hash" "$STACK_DIR/admin/auth/password.hash"
  admin_perms
fi

mkdir -p "$STACK_DIR/import-reference"
for p in .env zurg rclone; do [ -e "$tmp/$p" ] && cp -a "$tmp/$p" "$STACK_DIR/import-reference/"; done
chown -R root:root "$STACK_DIR/import-reference"; chmod -R go-rwx "$STACK_DIR/import-reference"

rm -f "$STACK_DIR/MAINTENANCE"
compose up -d >>"$LOG" 2>&1
# Point Plex at this machine (LAN networks, custom URL) and re-check the libraries
bash "$STACK_DIR/scripts/plex-setup.sh"
log "import: restored from $(basename "$arc")"
echo
echo "Done. Old settings for reference: $STACK_DIR/import-reference/ (contains secrets; delete when no longer needed)."
echo "Previous Plex config kept in: plex/config.before-import-$stamp (delete once everything works)."
