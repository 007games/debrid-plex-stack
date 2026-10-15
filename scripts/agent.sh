#!/bin/bash
# Host-side agent for the management page (runs as root).
# - Applies requests the page queued in admin/requests (whitelisted actions only).
# - Publishes admin/state/{status.json,log.txt,results.log,backups/} for the page.
# The page itself has no Docker access and never sees saved keys.
# Started by the watchdog (every minute) and, on systemd hosts, instantly by debrid-agent.path.
. "$(dirname "$0")/common.sh"

ADMIN="$STACK_DIR/admin"
REQ="$ADMIN/requests"
STATE="$ADMIN/state"
[ -d "$REQ" ] || exit 0

exec 8>/tmp/debrid-agent.lock
flock -n 8 || exit 0
mkdir -p "$STATE/backups"
chmod 755 "$STATE" "$STATE/backups"

result() {  # result ACTION OK|FAIL MESSAGE
  printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$1" "$2" "$(echo "$3" | tr '\t\n' '  ' | cut -c1-200)" >>"$STATE/results.log"
  tail -n 50 "$STATE/results.log" >"$STATE/results.tmp" && mv -f "$STATE/results.tmp" "$STATE/results.log"
  chmod 644 "$STATE/results.log"
  log "agent: $1 $2 $3"
}

field() { sed -n "s/^$1=//p" "$2" | head -1; }

do_backup() {
  local out="$STATE/backups/$PROVIDER-$(date +%F-%H%M).json" token key
  if [ "$PROVIDER" = realdebrid ]; then
    command -v python3 >/dev/null || { echo "python3 is not installed on the host"; return 1; }
    token=$(sed -n 's/^token: //p' "$STACK_DIR/zurg/config.yml" | tr -d '\r')
    RD_TOKEN="$token" python3 "$STACK_DIR/tools/rd.py" backup -o "$out" || return 1
  else
    key=$(envval TORBOX_API_KEY)
    curl -fsS --max-time 60 -H "Authorization: Bearer $key" \
      "https://api.torbox.app/v1/api/torrents/mylist?bypass_cache=true" >"$out" || { rm -f "$out"; echo "TorBox API request failed"; return 1; }
  fi
  chmod 644 "$out"
  ls -1t "$STATE/backups"/*.json 2>/dev/null | tail -n +11 | xargs -r rm -f   # keep the newest 10
  echo "saved $(basename "$out")"
}

# ------------------------------------------------------------------ requests

# Leftovers from an interrupted write (the page writes .tmp, then renames to .req)
find "$REQ" -mindepth 1 -maxdepth 1 ! -name '*.req' -mmin +5 -exec rm -rf {} + 2>/dev/null

count=0
for f in "$REQ"/*.req; do
  [ -e "$f" ] || continue
  # The page's container owns this directory: never follow links or read big files
  if [ -L "$f" ] || [ ! -f "$f" ] || [ "$(stat -c %s "$f")" -gt 1024 ]; then
    rm -f "$f"; result invalid FAIL "rejected request file"; continue
  fi
  count=$((count + 1))
  action=$(field action "$f"); value=$(field value "$f")
  rm -f "$f"
  [ "$count" -gt 10 ] && { result "$action" FAIL "too many requests at once"; continue; }
  [[ "$action" =~ ^[a-z_]{1,30}$ ]] || { result invalid FAIL "bad action name"; continue; }
  [[ "$value" =~ ^[A-Za-z0-9_-]{0,100}$ ]] || { result "$action" FAIL "bad value"; continue; }

  rc=0
  case "$action" in
    set_rd_token)    out=$(bash "$STACK_DIR/scripts/set-key.sh" realdebrid "$value" 2>&1) || rc=1 ;;
    set_torbox_key)  out=$(bash "$STACK_DIR/scripts/set-key.sh" torbox "$value" 2>&1) || rc=1 ;;
    switch_provider) out=$(bash "$STACK_DIR/scripts/switch-provider.sh" "$value" 2>&1) || rc=1 ;;
    restart)         out=$(compose restart 2>&1) || rc=1; [ $rc = 0 ] && out="restarted" ;;
    maintenance_on)  touch "$STACK_DIR/MAINTENANCE"; out="watchdog paused" ;;
    maintenance_off) rm -f "$STACK_DIR/MAINTENANCE"; out="watchdog active" ;;
    plex_setup)      out=$(bash "$STACK_DIR/scripts/plex-setup.sh" 2>&1) || rc=1 ;;
    backup)          out=$(do_backup 2>&1) || rc=1 ;;
    *)               result "$action" FAIL "unknown action"; continue ;;
  esac
  out=$(echo "$out" | tail -n 1)
  if [ $rc = 0 ]; then result "$action" OK "$out"; else result "$action" FAIL "$out"; fi
  case "$action" in set_*|switch_provider) rm -f "$STATE/.account" ;; esac
  # Re-read settings in case a provider switch changed them
  . "$STACK_DIR/scripts/common.sh"
done

# -------------------------------------------------------------------- status

account_json() {  # cached for 15 minutes; one API call
  local cache="$STATE/.account" token key resp secs exp
  if [ -f "$cache" ] && [ $(( $(date +%s) - $(stat -c %Y "$cache") )) -lt 900 ]; then cat "$cache"; return; fi
  if [ "$PROVIDER" = realdebrid ]; then
    token=$(sed -n 's/^token: //p' "$STACK_DIR/zurg/config.yml" 2>/dev/null | tr -d '\r')
    resp=$(curl -fsS --max-time 10 -H "Authorization: Bearer $token" https://api.real-debrid.com/rest/1.0/user 2>/dev/null | tr -d '\n')
    secs=$(echo "$resp" | sed -n 's/.*"premium"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
    exp=$(echo "$resp" | sed -n 's/.*"expiration"[[:space:]]*:[[:space:]]*"\([0-9-]*\).*/\1/p')
    [ -n "$secs" ] && printf '{"ok": true, "days_left": %d, "expires": "%s"}' "$((secs / 86400))" "$(js "$exp")" >"$cache"
  else
    key=$(envval TORBOX_API_KEY)
    resp=$(curl -fsS --max-time 10 -H "Authorization: Bearer $key" https://api.torbox.app/v1/api/user/me 2>/dev/null | tr -d '\n')
    exp=$(echo "$resp" | sed -n 's/.*"premium_expires_at"[[:space:]]*:[[:space:]]*"\([0-9-]*\).*/\1/p')
    if echo "$resp" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
      local end
      end=$(date -d "$exp" +%s 2>/dev/null)
      if [ -n "$end" ]; then
        printf '{"ok": true, "days_left": %d, "expires": "%s"}' "$(( (end - $(date +%s)) / 86400 ))" "$(js "$exp")" >"$cache"
      else
        printf '{"ok": true, "expires": "%s"}' "$(js "$exp")" >"$cache"
      fi
    fi
  fi
  [ -f "$cache" ] && cat "$cache" || printf '{"ok": false}'
}

key_hint() {
  local k
  if [ "$PROVIDER" = realdebrid ]; then k=$(sed -n 's/^token: //p' "$STACK_DIR/zurg/config.yml" 2>/dev/null)
  else k=$(envval TORBOX_API_KEY); fi
  k=$(printf '%s' "$k" | tr -dc 'A-Za-z0-9_-')
  [ ${#k} -gt 8 ] && echo "${k: -4}"
}

# Only plain characters go into status.json
js() { printf '%s' "$1" | tr -dc 'A-Za-z0-9 ._:()/-'; }

# Premium expiry: shown on the page, and logged once a day when it gets close
WARN_DAYS=$(envval EXPIRY_WARN_DAYS); [[ "$WARN_DAYS" =~ ^[0-9]{1,3}$ ]] || WARN_DAYS=7
ACCOUNT=$(account_json)
days_left=$(printf '%s' "$ACCOUNT" | sed -n 's/.*"days_left": *\(-\{0,1\}[0-9]*\).*/\1/p')
if [ -n "$days_left" ] && [ "$days_left" -le "$WARN_DAYS" ]; then
  marker="$STATE/.expiry-logged-$(date +%F)"
  if [ ! -f "$marker" ]; then
    rm -f "$STATE"/.expiry-logged-*
    touch "$marker"
    name=$([ "$PROVIDER" = torbox ] && echo TorBox || echo Real-Debrid)
    if [ "$days_left" -le 0 ]; then log "warning: $name premium has EXPIRED; streaming stops until you renew"
    else log "warning: $name premium expires in $days_left day(s)"; fi
  fi
fi

{
  printf '{\n  "updated": "%s",\n  "provider": "%s",\n' "$(date '+%F %T')" "$(js "$PROVIDER")"
  printf '  "maintenance": %s,\n' "$([ -f "$STACK_DIR/MAINTENANCE" ] && echo true || echo false)"
  printf '  "containers": {'
  sep=""
  for c in $SERVICES; do
    st=$("$DOCKER" inspect -f '{{.State.Status}}{{if .State.Health}} ({{.State.Health.Status}}){{end}}' "$c" 2>/dev/null)
    printf '%s"%s": "%s"' "$sep" "$c" "$(js "${st:-missing}")"; sep=", "
  done
  printf '},\n  "mount_ok": %s,\n' "$(mount_ok && echo true || echo false)"
  printf '  "items": {'
  sep=""
  for d in $LIBRARY_DIRS; do
    n=$(timeout 20 ls "$MNT/$d" 2>/dev/null | wc -l)
    printf '%s"%s": %d' "$sep" "$d" "${n:-0}"; sep=", "
  done
  printf '},\n  "dockerd_mb": %d,\n' "$(dockerd_rss_mb || echo 0)"
  printf '  "key_hint": "%s",\n' "$(key_hint)"
  printf '  "rd_key_set": %s,\n' "$(grep -q '^token: [A-Za-z0-9]' "$STACK_DIR/zurg/config.yml" 2>/dev/null && echo true || echo false)"
  printf '  "torbox_key_set": %s,\n' "$([ -n "$(envval TORBOX_API_KEY)" ] && echo true || echo false)"
  printf '  "expiry_warn_days": %d,\n' "$WARN_DAYS"
  printf '  "account": %s\n}\n' "$ACCOUNT"
} >"$STATE/status.tmp" && mv -f "$STATE/status.tmp" "$STATE/status.json"
chmod 644 "$STATE/status.json"

tail -n 100 "$LOG" 2>/dev/null >"$STATE/log.txt"
chmod 644 "$STATE/log.txt"

# Current keys for the page's "Show key" (behind password re-entry). Only the page's
# user (65534) can read admin/secret; nothing secret goes into admin/state.
publish_secret() {  # publish_secret NAME VALUE
  local f="$ADMIN/secret/$1"
  if [ -z "$2" ]; then rm -f "$f"; return; fi
  [ -f "$f" ] && [ "$(cat "$f")" = "$2" ] && return
  printf '%s' "$2" >"$f.tmp" && chown 65534:65534 "$f.tmp" && chmod 600 "$f.tmp" && mv -f "$f.tmp" "$f"
}
if [ -d "$ADMIN/secret" ]; then
  publish_secret rd.key "$(sed -n 's/^token: //p' "$STACK_DIR/zurg/config.yml" 2>/dev/null | tr -dc 'A-Za-z0-9_-')"
  publish_secret torbox.key "$(envval TORBOX_API_KEY | tr -dc 'A-Za-z0-9_-')"
fi
