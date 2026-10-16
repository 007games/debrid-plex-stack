#!/bin/bash
# Host-side agent for the management page (runs as root).
# - Applies requests the page queued in admin/requests (whitelisted actions only).
# - Publishes admin/state/{status.json,log.txt,results.log,backups/} for the page.
# Started by the watchdog (every minute) and, on systemd hosts, instantly by debrid-agent.path.
#
# Safety rule: the page's container can write to admin/requests (and possibly
# admin/state), so a compromised page could plant symlinks there. This script
# therefore never writes, reads or chmods *through* a path in those folders:
# files are built in the root-only admin/.agent folder and renamed into place
# (a rename replaces a symlink instead of following it).
. "$(dirname "$0")/common.sh"

ADMIN="$STACK_DIR/admin"
REQ="$ADMIN/requests"
STATE="$ADMIN/state"
PRIV="$ADMIN/.agent"            # root-only: caches, markers, temp files
[ -d "$REQ" ] || exit 0

# Hold the lock in a separate flock process (-o): anything this script starts in the
# background must not inherit the lock, or the agent stays blocked while it runs
if [ -z "${DEBRID_AGENT_LOCKED:-}" ]; then
  DEBRID_AGENT_LOCKED=1 exec flock -n -o /tmp/debrid-agent.v2.lock bash "$0" "$@"
fi

umask 022
if [ -L "$PRIV" ] || { [ -e "$PRIV" ] && [ ! -d "$PRIV" ]; }; then rm -f "$PRIV"; fi
mkdir -p "$PRIV" && chown root:root "$PRIV" && chmod 700 "$PRIV"
# One-time: carry over the action history from the old location (only a root-owned regular file)
if [ ! -f "$PRIV/results.log" ] && [ -f "$STATE/results.log" ] && [ ! -L "$STATE/results.log" ]    && [ "$(stat -c %u "$STATE/results.log")" = 0 ]; then
  head -c 20000 "$STATE/results.log" >"$PRIV/results.log"
fi

# A real directory (not a planted symlink) inside STATE
safe_dir() {
  local d="$STATE/$1"
  if [ -L "$d" ] || { [ -e "$d" ] && [ ! -d "$d" ]; }; then rm -f "$d"; fi
  mkdir -p "$d"
}

# put SRC NAME: publish a root-built file into STATE atomically, without following links
put() {
  chmod 644 "$1"
  mv -fT "$1" "$STATE/$2" 2>/dev/null || { rm -f "$STATE/$2"; mv -f "$1" "$STATE/$2"; }
}

result() {  # result ACTION OK|FAIL MESSAGE (master copy lives in PRIV)
  printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$1" "$2" "$(echo "$3" | tr '\t\n' '  ' | cut -c1-200)" >>"$PRIV/results.log"
  tail -n 50 "$PRIV/results.log" >"$PRIV/results.trim" && mv -f "$PRIV/results.trim" "$PRIV/results.log"
  cp "$PRIV/results.log" "$PRIV/results.pub" && put "$PRIV/results.pub" results.log
  log "agent: $1 $2 $3"
}

field() { sed -n "s/^$1=//p" "$2" | head -1; }

do_backup() {
  local name tmp="$PRIV/backup.tmp" token key
  name="$PROVIDER-$(date +%F-%H%M).json"
  if [ "$PROVIDER" = realdebrid ]; then
    command -v python3 >/dev/null || { echo "python3 is not installed on the host"; return 1; }
    token=$(sed -n 's/^token: //p' "$STACK_DIR/zurg/config.yml" | tr -d '\r')
    RD_TOKEN="$token" python3 "$STACK_DIR/tools/rd.py" backup -o "$tmp" >/dev/null || { rm -f "$tmp"; return 1; }
  else
    key=$(envval TORBOX_API_KEY)
    curl -fsS --max-time 60 -H "Authorization: Bearer $key" \
      "https://api.torbox.app/v1/api/torrents/mylist?bypass_cache=true" >"$tmp" || { rm -f "$tmp"; echo "TorBox API request failed"; return 1; }
  fi
  safe_dir backups
  put "$tmp" "backups/$name"
  # Keep the newest 10 of *our* backups (names carry the timestamp, so sort by name)
  find "$STATE/backups" -maxdepth 1 \( -type f -o -type l \) -regextype posix-extended \
       -regex '.*/(realdebrid|torbox)-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}\.json' -printf '%f\n' 2>/dev/null \
    | sort -r | tail -n +11 | while read -r old; do rm -f -- "$STATE/backups/$old"; done
  echo "saved $name"
}

# rd.py with the current Real-Debrid key (passed in the environment, never as an argument)
rdpy() {
  [ "$PROVIDER" = realdebrid ] || { echo "only available with Real-Debrid"; return 1; }
  command -v python3 >/dev/null || { echo "python3 is not installed on the host"; return 1; }
  RD_TOKEN="$(sed -n 's/^token: //p' "$STACK_DIR/zurg/config.yml" | tr -d '\r')" python3 "$STACK_DIR/tools/rd.py" "$@"
}

# Duplicate report for the page (built in PRIV, published to STATE)
do_duplicates() {  # do_duplicates [--remove-exact]
  rdpy duplicates --json "$PRIV/duplicates.json" "$@" || return 1
  put "$PRIV/duplicates.json" duplicates.json
}

# ------------------------------------------------------------------ requests

# Leftovers from an interrupted write (the page writes .tmp, then renames to .req)
find "$REQ" -mindepth 1 -maxdepth 1 ! -name '*.req' -mmin +5 -exec rm -rf {} + 2>/dev/null

count=0
for f in "$REQ"/*.req; do
  [ -e "$f" ] || [ -L "$f" ] || continue
  # Move it out of the page's reach first (rename never follows links), then inspect
  mv -fT "$f" "$PRIV/req" 2>/dev/null || { rm -f "$f"; continue; }
  if [ -L "$PRIV/req" ] || [ ! -f "$PRIV/req" ] || [ "$(stat -c %s "$PRIV/req")" -gt 1024 ]; then
    rm -f "$PRIV/req"; result invalid FAIL "rejected request file"; continue
  fi
  count=$((count + 1))
  action=$(field action "$PRIV/req"); value=$(field value "$PRIV/req")
  rm -f "$PRIV/req"
  [ "$count" -gt 10 ] && { result "$action" FAIL "too many requests at once"; continue; }
  [[ "$action" =~ ^[a-z_]{1,30}$ ]] || { result invalid FAIL "bad action name"; continue; }
  [[ "$value" =~ ^[A-Za-z0-9_-]{0,100}$ ]] || { result "$action" FAIL "bad value"; continue; }

  # Tell the page what is running (cleared when done)
  printf '%s\t%s\n' "$action" "$(date '+%F %T')" >"$PRIV/busy" && put "$PRIV/busy" busy.txt
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
    scan_duplicates) out=$(do_duplicates 2>&1) || rc=1 ;;
    remove_exact_duplicates) out=$(do_duplicates --remove-exact 2>&1) || rc=1 ;;
    delete_torrent)  out=$(rdpy delete "$value" 2>&1) || rc=1; do_duplicates >/dev/null 2>&1 ;;
    *)               result "$action" FAIL "unknown action"; continue ;;
  esac
  out=$(echo "$out" | tail -n 1)
  if [ $rc = 0 ]; then result "$action" OK "$out"; else result "$action" FAIL "$out"; fi
  rm -f "$STATE/busy.txt"
  case "$action" in set_*|switch_provider) rm -f "$PRIV/account" ;; esac
  # Re-read settings in case a provider switch changed them
  . "$STACK_DIR/scripts/common.sh"
done

# -------------------------------------------------------------------- status

# Only plain characters go into status.json
js() { printf '%s' "$1" | tr -dc 'A-Za-z0-9 ._:()/-'; }

account_json() {  # cached for 15 minutes in PRIV; one API call
  local cache="$PRIV/account" token key resp secs exp end
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

# Premium expiry: shown on the page, and logged once a day when it gets close
WARN_DAYS=$(envval EXPIRY_WARN_DAYS); [[ "$WARN_DAYS" =~ ^[0-9]{1,3}$ ]] || WARN_DAYS=7
ACCOUNT=$(account_json)
days_left=$(printf '%s' "$ACCOUNT" | sed -n 's/.*"days_left": *\(-\{0,1\}[0-9]*\).*/\1/p')
if [ -n "$days_left" ] && [ "$days_left" -le "$WARN_DAYS" ]; then
  marker="$PRIV/expiry-logged-$(date +%F)"
  if [ ! -f "$marker" ]; then
    rm -f "$PRIV"/expiry-logged-*
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
} >"$PRIV/status.json" && put "$PRIV/status.json" status.json

tail -n 100 "$LOG" 2>/dev/null >"$PRIV/log.txt" && put "$PRIV/log.txt" log.txt

# Old-style files the agent used to keep in STATE (now in PRIV)
rm -f "$STATE/.account" "$STATE"/.expiry-logged-* "$STATE/status.tmp" "$STATE/results.tmp"

# Current keys for the page's "Show key" (behind password re-entry). Only the page's
# user (65534) can read admin/secret; nothing secret goes into admin/state.
publish_secret() {  # publish_secret NAME VALUE
  local f="$ADMIN/secret/$1" tmp="$PRIV/secret.tmp"
  if [ -z "$2" ]; then rm -f "$f"; return; fi
  [ -f "$f" ] && [ ! -L "$f" ] && [ "$(cat "$f")" = "$2" ] && return
  printf '%s' "$2" >"$tmp" && chown 65534:65534 "$tmp" && chmod 600 "$tmp" \
    && { mv -fT "$tmp" "$f" 2>/dev/null || { rm -f "$f"; mv -f "$tmp" "$f"; }; }
}
if [ -d "$ADMIN/secret" ] && [ ! -L "$ADMIN/secret" ]; then
  publish_secret rd.key "$(sed -n 's/^token: //p' "$STACK_DIR/zurg/config.yml" 2>/dev/null | tr -dc 'A-Za-z0-9_-')"
  publish_secret torbox.key "$(envval TORBOX_API_KEY | tr -dc 'A-Za-z0-9_-')"
fi
