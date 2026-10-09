#!/bin/bash
# debrid-plex-stack installer: Real-Debrid -> Zurg -> rclone -> Plex, isolated and LAN-only.
#
#   curl -fsSL https://raw.githubusercontent.com/007games/debrid-plex-stack/main/install.sh | sudo bash
#
# Optional environment variables:
#   PROVIDER               realdebrid (default) or torbox (experimental)
#   RD_TOKEN / TORBOX_API_KEY, PLEX_CLAIM   skip the prompts (non-interactive install)
#   DEBRID_DIR             install location (default: /volume1/@debrid on Synology, else /opt/debrid)
#   PLEX_LANGUAGE          library metadata language (default: en-US)
#   DEBRID_SRC             use a local checkout instead of downloading from GitHub
# Run with --check to only print what would be detected.

set -euo pipefail

REPO="007games/debrid-plex-stack"
BRANCH="${DEBRID_BRANCH:-main}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*"; }
die()  { printf '\033[31mError: %s\033[0m\n' "$*" >&2; exit 1; }

ask() {  # ask VAR "prompt" [secret]
  local var=$1 prompt=$2 val
  [ -n "${!var:-}" ] && return 0
  [ -r /dev/tty ] || die "no terminal to ask for $var; set it as an environment variable"
  if [ -n "${3:-}" ]; then read -rsp "$prompt" val </dev/tty; echo >/dev/tty
  else read -rp "$prompt" val </dev/tty; fi
  printf -v "$var" '%s' "$val"
}

# ------------------------------------------------------------------ detection

detect() {
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  SYNOLOGY=no; [ -d /usr/syno ] && SYNOLOGY=yes
  if [ -z "${DEBRID_DIR:-}" ]; then
    if [ "$SYNOLOGY" = yes ] && [ -d /volume1 ]; then DEBRID_DIR=/volume1/@debrid; else DEBRID_DIR=/opt/debrid; fi
  fi

  LAN_IFACE=$(ip route | awk '/^default/ {print $5; exit}')
  local cidr; cidr=$(ip -o -f inet addr show "$LAN_IFACE" | awk '{print $4; exit}')
  LAN_IP=${cidr%/*}
  local bits=${cidr#*/} a b c d n mask
  IFS=. read -r a b c d <<<"$LAN_IP"
  n=$(( (a << 24) | (b << 16) | (c << 8) | d ))
  mask=$(( (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))
  n=$(( n & mask ))
  LAN_SUBNET="$(( n >> 24 & 255 )).$(( n >> 16 & 255 )).$(( n >> 8 & 255 )).$(( n & 255 ))/$bits"

  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    PUID=$(id -u "$SUDO_USER"); PGID=$(id -g "$SUDO_USER")
  else
    PUID=1000; PGID=1000
  fi

  TZ_NAME=$(cat /etc/timezone 2>/dev/null || readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' || true)
  TZ_NAME=${TZ_NAME:-UTC}

  GPU=no; [ -e /dev/dri/renderD128 ] && GPU=yes

  PLEX_SUBNET=172.30.0.0/24; PLEX_GATEWAY=172.30.0.1
  if ip route | grep -q '^172\.30\.0\.' && ! docker network inspect debrid_plex_lan >/dev/null 2>&1; then
    PLEX_SUBNET=172.30.250.0/24; PLEX_GATEWAY=172.30.250.1
  fi
}

show() {
  bold "Detected"
  info "platform:     $([ "$SYNOLOGY" = yes ] && echo Synology DSM || echo Linux)"
  info "install dir:  $DEBRID_DIR"
  info "LAN:          $LAN_IP on $LAN_IFACE ($LAN_SUBNET)"
  info "user:         PUID=$PUID PGID=$PGID"
  info "timezone:     $TZ_NAME"
  info "GPU (/dev/dri): $GPU"
  info "Plex network: $PLEX_SUBNET"
}

preflight() {
  [ "$(id -u)" = 0 ] || die "run as root (sudo)"
  command -v docker >/dev/null || die "Docker is not installed (Synology: install Container Manager)"
  docker compose version >/dev/null 2>&1 || die "the Docker Compose v2 plugin is missing"
  [ -e /dev/fuse ] || die "/dev/fuse not found (FUSE is required)"
  command -v curl >/dev/null || die "curl is required"
  [ -n "$LAN_IP" ] || die "could not detect the LAN IP"
  command -v iptables >/dev/null || warn "iptables not found: port 32400 won't be limited to your LAN"

  local c project
  for c in zurg rclone plex; do
    project=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$c" 2>/dev/null || true)
    if docker inspect "$c" >/dev/null 2>&1 && [ "$project" != debrid ]; then
      die "a container named '$c' already exists and isn't part of this stack; remove or rename it first"
    fi
  done
}

# -------------------------------------------------------------------- install

fetch() {
  bold "Installing to $DEBRID_DIR"
  mkdir -p "$DEBRID_DIR"
  SRC=${DEBRID_SRC:-}
  if [ -z "$SRC" ]; then
    SRC=$(mktemp -d)
    trap 'rm -rf "$SRC"' EXIT
    curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar xz -C "$SRC" --strip-components=1
  fi
  cp -R "$SRC/." "$DEBRID_DIR/"
  rm -rf "$DEBRID_DIR/.git" "$DEBRID_DIR/.github"
  mkdir -p "$DEBRID_DIR"/{zurg/data,rclone/cache,plex/config,mnt/zurg,mnt/torbox,logs}
}

check_rd_token() {
  local resp
  resp=$(curl -fsS --max-time 15 -H "Authorization: Bearer $RD_TOKEN" https://api.real-debrid.com/rest/1.0/user) \
    || die "Real-Debrid rejected the token (get it at https://real-debrid.com/apitoken)"
  echo "$resp" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"premium"' || die "this Real-Debrid account has no active Premium"
  resp=$(echo "$resp" | tr -d '\n')
  info "Real-Debrid: $(echo "$resp" | sed -n 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'), premium until $(echo "$resp" | sed -n 's/.*"expiration"[[:space:]]*:[[:space:]]*"\([0-9-]*\).*/\1/p')"
}

check_torbox_key() {
  local resp
  resp=$(curl -fsS --max-time 15 -H "Authorization: Bearer $TORBOX_API_KEY" https://api.torbox.app/v1/api/user/me) \
    || die "TorBox rejected the API key (get it at https://torbox.app/settings)"
  echo "$resp" | grep -Eq '"success"[[:space:]]*:[[:space:]]*true' || die "TorBox rejected the API key"
  echo "$resp" | grep -Eq '"plan"[[:space:]]*:[[:space:]]*0[,}]' && warn "this looks like a free TorBox plan; the mount needs a paid plan"
  info "TorBox: API key accepted"
}

choose_provider() {
  if [ -z "${PROVIDER:-}" ]; then
    if [ -n "${RD_TOKEN:-}" ]; then PROVIDER=realdebrid
    elif [ -n "${TORBOX_API_KEY:-}" ]; then PROVIDER=torbox
    else
      local pick
      info "Which debrid service?  1) Real-Debrid (default)   2) TorBox (experimental)"
      ask pick "Choice [1]: "
      case "$pick" in 2|torbox|TorBox) PROVIDER=torbox ;; *) PROVIDER=realdebrid ;; esac
    fi
  fi
  case "$PROVIDER" in realdebrid|torbox) ;; *) die "PROVIDER must be realdebrid or torbox" ;; esac
}

configure() {
  cd "$DEBRID_DIR"
  if [ -f .env ]; then
    info "existing .env found: keeping your settings and secrets"
    return
  fi
  bold "Configuration"
  choose_provider

  local extra=""
  if [ "$PROVIDER" = realdebrid ]; then
    ask RD_TOKEN "Real-Debrid API token (https://real-debrid.com/apitoken): " secret
    check_rd_token
    local pw obscured rclone_image
    pw=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-32)
    rclone_image=$(sed -n 's/.*RCLONE_IMAGE:-\([^}]*\)}.*/\1/p' provider-realdebrid.yml)
    obscured=$(docker run --rm "$rclone_image" obscure "$pw")
    sed -e "s|__RD_TOKEN__|$RD_TOKEN|" -e "s|__WEBDAV_PASS__|$pw|" zurg/config.yml.template >zurg/config.yml
    sed -e "s|__WEBDAV_PASS_OBSCURED__|$obscured|" rclone/rclone.conf.template >rclone/rclone.conf
    extra="RCLONE_CACHE_MAX=20G"
  else
    ask TORBOX_API_KEY "TorBox API key (https://torbox.app/settings): " secret
    check_torbox_key
    extra=$(printf 'TORBOX_API_KEY=%s\nTORBOX_REFRESH=fast' "$TORBOX_API_KEY")
  fi

  local compose_file="docker-compose.yml:provider-$PROVIDER.yml"
  [ "$GPU" = yes ] && compose_file="$compose_file:compose.gpu.yml"
  cat >.env <<EOF
# Generated by install.sh
PROVIDER=$PROVIDER
COMPOSE_FILE=$compose_file
PUID=$PUID
PGID=$PGID
TZ=$TZ_NAME
LAN_IP=$LAN_IP
LAN_IFACE=$LAN_IFACE
LAN_SUBNET=$LAN_SUBNET
PLEX_SUBNET=$PLEX_SUBNET
PLEX_GATEWAY=$PLEX_GATEWAY
PLEX_LANGUAGE=${PLEX_LANGUAGE:-en-US}
PLEX_CLAIM=
$extra
EOF
}

secure() {
  cd "$DEBRID_DIR"
  chown -R root:root "$DEBRID_DIR"
  chmod 711 "$DEBRID_DIR"
  chmod 700 zurg zurg/data rclone rclone/cache logs scripts
  chmod 600 .env
  chmod 600 zurg/config.yml rclone/rclone.conf 2>/dev/null || true
  chmod 700 scripts/*.sh install.sh uninstall.sh
  chown -R "$PUID:$PGID" plex
  chmod 750 plex plex/config
  chmod 755 mnt mnt/zurg mnt/torbox
}

start() {
  cd "$DEBRID_DIR"
  bold "Pulling images (first time: ~1 GB)"
  docker compose pull -q

  local prefs="plex/config/Library/Application Support/Plex Media Server/Preferences.xml"
  if ! grep -q 'PlexOnlineToken="' "$prefs" 2>/dev/null; then
    bold "Link Plex to your account"
    info "Open https://plex.tv/claim, sign in and copy the code (valid 4 minutes)."
    ask PLEX_CLAIM "Plex claim code (claim-...): "
    sed -i "s|^PLEX_CLAIM=.*|PLEX_CLAIM=$PLEX_CLAIM|" .env
  fi

  bold "Starting"
  bash scripts/boot.sh
  tail -n 3 logs/debrid.log | sed 's/^/  /'
  bash scripts/plex-setup.sh || warn "Plex setup incomplete (see message above)"
}

persist() {
  bold "Start on boot + watchdog"
  if [ "$SYNOLOGY" = yes ]; then
    info "Synology: create two tasks in Control Panel > Task Scheduler > Create (user: root):"
    info "  1. Triggered Task, event Boot-up:          bash $DEBRID_DIR/scripts/boot.sh"
    info "  2. Scheduled Task, daily, every 5 minutes: bash $DEBRID_DIR/scripts/watchdog.sh"
  elif command -v systemctl >/dev/null && [ -d /etc/systemd/system ]; then
    cat >/etc/systemd/system/debrid-boot.service <<EOF
[Unit]
Description=debrid-plex-stack: shared mount, firewall, start containers
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash $DEBRID_DIR/scripts/boot.sh

[Install]
WantedBy=multi-user.target
EOF
    cat >/etc/systemd/system/debrid-watchdog.service <<EOF
[Unit]
Description=debrid-plex-stack watchdog

[Service]
Type=oneshot
ExecStart=/bin/bash $DEBRID_DIR/scripts/watchdog.sh
EOF
    cat >/etc/systemd/system/debrid-watchdog.timer <<EOF
[Unit]
Description=Run the debrid-plex-stack watchdog every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable debrid-boot.service >/dev/null 2>&1
    systemctl enable --now debrid-watchdog.timer >/dev/null 2>&1
    info "systemd: debrid-boot.service and debrid-watchdog.timer enabled"
  else
    warn "no systemd: run scripts/boot.sh at boot and scripts/watchdog.sh every 5 minutes yourself"
  fi
}

summary() {
  echo
  bold "Done."
  info "Plex:    http://$LAN_IP:32400/web   (LAN only, remote access off)"
  if [ "$(sed -n 's/^PROVIDER=//p' "$DEBRID_DIR/.env")" = torbox ]; then
    info "Add titles in your TorBox dashboard; they appear after the next mount refresh (~2 h) and Plex scan."
  else
    info "Add titles to Real-Debrid (e.g. https://debridmediamanager.com); they appear within ~15 min."
  fi
  info "Health:  sudo bash $DEBRID_DIR/scripts/status.sh"
  info "Remove:  sudo bash $DEBRID_DIR/uninstall.sh"
}

main() {
  detect
  if [ "${1:-}" = "--check" ]; then show; exit 0; fi
  preflight
  show
  fetch
  configure
  secure
  start
  persist
  summary
}

main "$@"
