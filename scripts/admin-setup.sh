#!/bin/bash
# Set up (or reset the password of) the management page.
#   sudo bash scripts/admin-setup.sh            enable, or reset the password
#   ADMIN_PASSWORD=... sudo -E bash scripts/admin-setup.sh   non-interactive
. "$(dirname "$0")/common.sh"

[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }
cd "$STACK_DIR" || exit 1
A="$STACK_DIR/admin"
mkdir -p "$A/requests" "$A/state/backups" "$A/auth"

pw=${ADMIN_PASSWORD:-}
if [ -z "$pw" ]; then
  [ -r /dev/tty ] || { echo "no terminal; set ADMIN_PASSWORD"; exit 1; }
  read -rsp "Management page password (min. 8 characters): " pw </dev/tty; echo >/dev/tty
  read -rsp "Repeat: " pw2 </dev/tty; echo >/dev/tty
  [ "$pw" = "$pw2" ] || { echo "passwords don't match"; exit 1; }
fi
[ ${#pw} -ge 8 ] || { echo "password must be at least 8 characters"; exit 1; }

# Build everything in a root-only folder and rename it into place: admin/auth is
# writable by the page, so never write through a path that could be a planted symlink
P="$A/.agent"; [ -L "$P" ] && rm -f "$P"; mkdir -p "$P"; chown root:root "$P"; chmod 700 "$P"
put_auth() { mv -fT "$1" "$A/auth/$2" 2>/dev/null || { rm -f "$A/auth/$2"; mv -f "$1" "$A/auth/$2"; }; }

image=$(sed -n 's/.*ADMIN_IMAGE:-\([^}]*\)}.*/\1/p' compose.admin.yml)
printf '%s\n' "$pw" | "$DOCKER" run --rm -i -v "$A/app.py:/app/app.py:ro" "$image" python /app/app.py hash >"$P/password.hash" \
  || { rm -f "$P/password.hash"; echo "could not hash the password"; exit 1; }
put_auth "$P/password.hash" password.hash
unset pw pw2

# Certificate: a local CA (install it once per device and the browser warning is gone)
# and a server certificate it signs; the agent renews it when it gets close to expiry
bash "$STACK_DIR/scripts/admin-cert.sh" || echo "warning: no certificate (openssl missing?), the page will use plain HTTP"

admin_perms

# Enable in .env
grep -q '^ADMIN_PORT=' .env || echo "ADMIN_PORT=8099" >>.env
grep -q 'compose.admin.yml' .env || sed -i 's|^\(COMPOSE_FILE=.*\)$|\1:compose.admin.yml|' .env

bash "$STACK_DIR/scripts/agent.sh"       # publish a first status
compose up -d admin >/dev/null 2>&1 || compose up -d admin
ensure_firewall
scheme=https; [ -f "$A/auth/cert.pem" ] || scheme=http
echo "Management page: $scheme://$(envval LAN_IP):$(envval ADMIN_PORT)  (LAN only)"
