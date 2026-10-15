#!/bin/bash
# Validate a provider API key against the provider, save it, and restart what uses it.
#   sudo bash scripts/set-key.sh realdebrid|torbox KEY
# Never prints the key.
. "$(dirname "$0")/common.sh"

provider=${1:-}; key=${2:-}
fail() { echo "$*"; exit 1; }

[[ "$key" =~ ^[A-Za-z0-9_-]{20,100}$ ]] || fail "key has an unexpected format"

case "$provider" in
  realdebrid)
    resp=$(curl -fsS --max-time 15 -H "Authorization: Bearer $key" https://api.real-debrid.com/rest/1.0/user 2>/dev/null) \
      || fail "Real-Debrid rejected the key"
    echo "$resp" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"premium"' || fail "this Real-Debrid account has no active Premium"

    cd "$STACK_DIR" || exit 1
    if [ -f zurg/config.yml ]; then
      sed -i "s|^token: .*|token: $key|" zurg/config.yml
    else
      # First Real-Debrid key on this install: generate the zurg/rclone pair
      pw=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-32)
      rclone_image=$(sed -n 's/.*RCLONE_IMAGE:-\([^}]*\)}.*/\1/p' provider-realdebrid.yml)
      obscured=$("$DOCKER" run --rm "$rclone_image" obscure "$pw") || fail "could not run rclone to obscure the password"
      sed -e "s|__RD_TOKEN__|$key|" -e "s|__WEBDAV_PASS__|$pw|" zurg/config.yml.template >zurg/config.yml
      sed -e "s|__WEBDAV_PASS_OBSCURED__|$obscured|" rclone/rclone.conf.template >rclone/rclone.conf
      grep -q '^RCLONE_CACHE_MAX=' .env || echo "RCLONE_CACHE_MAX=20G" >>.env
    fi
    chmod 600 zurg/config.yml rclone/rclone.conf
    if [ "$PROVIDER" = realdebrid ] && container_running zurg; then
      compose restart zurg >/dev/null 2>&1 || fail "key saved, but restarting zurg failed"
    fi
    echo "Real-Debrid key saved (…${key: -4})"
    ;;

  torbox)
    resp=$(curl -fsS --max-time 15 -H "Authorization: Bearer $key" https://api.torbox.app/v1/api/user/me 2>/dev/null) \
      || fail "TorBox rejected the key"
    echo "$resp" | grep -Eq '"success"[[:space:]]*:[[:space:]]*true' || fail "TorBox rejected the key"

    cd "$STACK_DIR" || exit 1
    if grep -q '^TORBOX_API_KEY=' .env; then
      sed -i "s|^TORBOX_API_KEY=.*|TORBOX_API_KEY=$key|" .env
    else
      printf 'TORBOX_API_KEY=%s\nTORBOX_REFRESH=fast\n' "$key" >>.env
    fi
    if [ "$PROVIDER" = torbox ] && container_running torbox; then
      compose up -d torbox >/dev/null 2>&1 || fail "key saved, but restarting torbox failed"
    fi
    echo "TorBox key saved (…${key: -4})"
    ;;

  *) fail "usage: set-key.sh realdebrid|torbox KEY" ;;
esac
