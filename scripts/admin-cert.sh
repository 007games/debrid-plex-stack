#!/bin/bash
# Certificate for the management page: a small local CA (install it once on each
# phone/PC and the "not private" warning is gone) and a server certificate it signs.
# Phones only trust server certificates that are short-lived (iOS: at most 825 days)
# and marked for TLS servers, hence the two-level setup.
#   sudo bash scripts/admin-cert.sh           create what is missing, renew when < 30 days are left
#   sudo bash scripts/admin-cert.sh --renew   new server certificate now (same CA)
#   sudo bash scripts/admin-cert.sh --new-ca  new CA + server certificate (re-install the CA on your devices)
# Download the CA from the page: /certificate (instructions) or /ca.crt (the file).
. "$(dirname "$0")/common.sh"
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }
command -v openssl >/dev/null || { echo "openssl is not installed"; exit 1; }

A="$STACK_DIR/admin"; P="$A/.agent"; IP=$(envval LAN_IP)
[ -n "$IP" ] || { echo "LAN_IP is missing in .env"; exit 1; }
mkdir -p "$A/auth"
[ -L "$P" ] && rm -f "$P"; mkdir -p "$P"; chown root:root "$P"; chmod 700 "$P"
# admin/auth is writable by the page: build files here and rename them into place
put_auth() { chown 65534:65534 "$1"; chmod 600 "$1"; mv -fT "$1" "$A/auth/$2" 2>/dev/null || { rm -f "$A/auth/$2"; mv -f "$1" "$A/auth/$2"; }; }

CA_KEY="$P/ca-key.pem"; CA_CRT="$P/ca.pem"
[ "${1:-}" = --new-ca ] && rm -f "$CA_KEY" "$CA_CRT"
made_ca=0
if [ ! -s "$CA_KEY" ] || [ ! -s "$CA_CRT" ]; then
  # Own config: with -addext, OpenSSL 1.1.1 also adds its default basicConstraints,
  # and a certificate with a duplicated extension fails validation
  cat >"$P/ca.cnf" <<EOF
[req]
prompt = no
distinguished_name = dn
x509_extensions = v3
[dn]
CN = debrid-admin local CA
[v3]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
EOF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 -config "$P/ca.cnf" \
    -keyout "$CA_KEY" -out "$CA_CRT" >/dev/null 2>&1 || { rm -f "$P/ca.cnf"; echo "could not create the CA"; exit 1; }
  rm -f "$P/ca.cnf"
  chmod 600 "$CA_KEY"
  made_ca=1
  echo "new CA created; install it on your devices (open /certificate on the page)"
fi
cp "$CA_CRT" "$P/ca.pub" && put_auth "$P/ca.pub" ca.pem   # the page serves this file

# Is the current server certificate still fine? (ours, not a link, > 30 days left)
need=$made_ca
[ "${1:-}" = --renew ] && need=1
if [ "$need" = 0 ]; then
  if [ ! -s "$A/auth/cert.pem" ] || [ -L "$A/auth/cert.pem" ] \
     || ! openssl verify -CAfile "$CA_CRT" "$A/auth/cert.pem" >/dev/null 2>&1 \
     || ! openssl x509 -in "$A/auth/cert.pem" -noout -checkend $((30 * 86400)) >/dev/null 2>&1; then
    need=1
  fi
fi
if [ "$need" = 0 ]; then
  echo "certificate is fine ($(openssl x509 -in "$A/auth/cert.pem" -noout -enddate | sed 's/notAfter=/expires /'))"
  exit 0
fi

cat >"$P/cert.ext" <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=IP:$IP
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
EOF
openssl req -new -newkey rsa:2048 -nodes -sha256 -subj "/CN=debrid-admin" -keyout "$P/key.pem" -out "$P/cert.csr" >/dev/null 2>&1 \
  && openssl x509 -req -in "$P/cert.csr" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial -CAserial "$P/ca.srl" \
       -days 800 -sha256 -extfile "$P/cert.ext" -out "$P/cert.pem" >/dev/null 2>&1 \
  || { rm -f "$P/cert.csr" "$P/cert.ext"; echo "could not create the server certificate"; exit 1; }
rm -f "$P/cert.csr" "$P/cert.ext"
put_auth "$P/key.pem" key.pem; put_auth "$P/cert.pem" cert.pem
echo "new server certificate for $IP (valid 800 days)"
log "admin-cert: new server certificate for $IP$([ "$made_ca" = 1 ] && echo ' (new CA)')"
# The page loads its certificate at start-up
if container_running debrid-admin; then compose restart admin >/dev/null 2>&1 && echo "management page restarted"; fi
