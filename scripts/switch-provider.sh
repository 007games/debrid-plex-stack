#!/bin/bash
# Switch the stack between Real-Debrid and TorBox. The target's key must be set first
# (scripts/set-key.sh). Plex keeps its database; libraries for the new paths are added.
#   sudo bash scripts/switch-provider.sh realdebrid|torbox
. "$(dirname "$0")/common.sh"

target=${1:-}
fail() { echo "$*"; exit 1; }

case "$target" in realdebrid|torbox) ;; *) fail "usage: switch-provider.sh realdebrid|torbox" ;; esac
[ "$target" = "$PROVIDER" ] && { echo "already using $target"; exit 0; }

if [ "$target" = realdebrid ]; then
  grep -q '^token: [A-Za-z0-9]' "$STACK_DIR/zurg/config.yml" 2>/dev/null || fail "set a Real-Debrid key first"
else
  [ -n "$(envval TORBOX_API_KEY)" ] || fail "set a TorBox key first"
fi

log "switch-provider: $PROVIDER -> $target"
touch "$STACK_DIR/MAINTENANCE"
compose down --remove-orphans >>"$LOG" 2>&1      # with the old COMPOSE_FILE, so the old mount stops too
unmount_stale

sed -i -e "s|^PROVIDER=.*|PROVIDER=$target|" \
       -e "s|provider-[a-z]*\.yml|provider-$target.yml|" "$STACK_DIR/.env"
rm -f "$STACK_DIR/MAINTENANCE"

bash "$STACK_DIR/scripts/boot.sh"
bash "$STACK_DIR/scripts/plex-setup.sh" >>"$LOG" 2>&1 || fail "switched, but Plex setup reported a problem (see log)"
echo "now using $target"
