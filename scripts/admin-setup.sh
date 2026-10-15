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

image=$(sed -n 's/.*ADMIN_IMAGE:-\([^}]*\)}.*/\1/p' compose.admin.yml)
printf '%s\n' "$pw" | "$DOCKER" run --rm -i -v "$A/app.py:/app/app.py:ro" "$image" python /app/app.py hash >"$A/auth/password.hash" \
  || { echo "could not hash the password"; exit 1; }
unset pw pw2

# Self-signed certificate for the LAN IP (browsers will warn once; that's expected)
if [ ! -f "$A/auth/cert.pem" ] && command -v openssl >/dev/null; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=debrid-admin" \
    -addext "subjectAltName=IP:$(envval LAN_IP)" \
    -keyout "$A/auth/key.pem" -out "$A/auth/cert.pem" >/dev/null 2>&1 \
  || openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=debrid-admin" \
    -keyout "$A/auth/key.pem" -out "$A/auth/cert.pem" >/dev/null 2>&1
fi
[ -f "$A/auth/cert.pem" ] || echo "warning: no openssl, the page will use plain HTTP"

admin_perms

# Enable in .env
grep -q '^ADMIN_PORT=' .env || echo "ADMIN_PORT=8099" >>.env
grep -q 'compose.admin.yml' .env || sed -i 's|^\(COMPOSE_FILE=.*\)$|\1:compose.admin.yml|' .env

bash "$STACK_DIR/scripts/agent.sh"       # publish a first status
compose up -d admin >/dev/null 2>&1 || compose up -d admin
ensure_firewall
scheme=https; [ -f "$A/auth/cert.pem" ] || scheme=http
echo "Management page: $scheme://$(envval LAN_IP):$(envval ADMIN_PORT)  (LAN only)"
