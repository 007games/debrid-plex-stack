#!/bin/bash
# Read-only health report:  sudo bash scripts/status.sh
. "$(dirname "$0")/common.sh"

ok()   { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }

echo "Provider: $PROVIDER"
echo "Containers"
for c in $SERVICES; do
  st=$("$DOCKER" inspect -f '{{.State.Status}}{{if .State.Health}} ({{.State.Health.Status}}){{end}}' "$c" 2>/dev/null)
  container_running "$c" && ok "$c: $st" || bad "$c: ${st:-missing}"
done

if [ "$PROVIDER" = realdebrid ]; then
  echo "Zurg"
  zurg_ok && ok "WebDAV answers on 127.0.0.1:9999" || bad "WebDAV not answering"
fi

echo "Mount ($MNT)"
mnt_is_shared && ok "mnt is a shared mount" || bad "mnt not shared (run scripts/boot.sh)"
if mount_ok; then
  ok "mounted and responding"
  for d in $LIBRARY_DIRS; do
    [ -d "$MNT/$d" ] && info "$d: $(timeout 20 ls "$MNT/$d" 2>/dev/null | wc -l) items"
  done
else
  bad "not mounted or not responding"
fi

echo "Plex"
lan_ip=$(envval LAN_IP)
sub=${MNT#"$STACK_DIR"}
"$DOCKER" exec plex test -d "$sub/$PROBE" 2>/dev/null && ok "plex sees $sub" || bad "plex does not see $sub"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$lan_ip:32400/identity")
[ "$code" = "200" ] && ok "http://$lan_ip:32400 answers" || bad "http://$lan_ip:32400 -> HTTP $code"
if [ -e /dev/dri/renderD128 ]; then
  "$DOCKER" exec plex test -r /dev/dri/renderD128 2>/dev/null && ok "GPU render node readable" || bad "GPU render node not readable in plex"
fi
"$DOCKER" exec plex sh -c 'touch /mnt/.w' 2>/dev/null && bad "/mnt is WRITABLE from plex" || ok "/mnt read-only in plex"

echo "Isolation"
if [ "$PROVIDER" = realdebrid ]; then
  "$DOCKER" exec rclone wget -q -T 5 -O /dev/null http://1.1.1.1 2>/dev/null && bad "rclone can reach the internet" || ok "rclone has no internet access"
fi
# shellcheck disable=SC2046
iptables -C DOCKER-USER $(firewall_rule) 2>/dev/null && ok "port 32400 limited to $(envval LAN_SUBNET)" || bad "DOCKER-USER rule missing"

echo "Resources"
info "dockerd RAM:  $(dockerd_rss_mb) MB"
[ "$PROVIDER" = realdebrid ] && info "rclone cache: $(du -sh "$STACK_DIR/rclone/cache" 2>/dev/null | cut -f1) (max $(envval RCLONE_CACHE_MAX))"
info "plex config:  $(du -sh "$STACK_DIR/plex/config" 2>/dev/null | cut -f1)"
"$DOCKER" stats --no-stream --format '        {{.Name}}: {{.MemUsage}}  CPU {{.CPUPerc}}' $SERVICES 2>/dev/null

echo "Recent log"
tail -n 5 "$LOG" 2>/dev/null | sed 's/^/        /'
