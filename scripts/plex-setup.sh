#!/bin/bash
# Applies safe Plex settings and creates the libraries. Run by install.sh after the
# server is claimed; safe to re-run:  sudo bash scripts/plex-setup.sh
. "$(dirname "$0")/common.sh"

PREFS="$STACK_DIR/plex/config/Library/Application Support/Plex Media Server/Preferences.xml"
LAN_IP=$(envval LAN_IP)
LANG_CODE=$(envval PLEX_LANGUAGE); LANG_CODE=${LANG_CODE:-en-US}

tries=1
[ -n "$(envval PLEX_CLAIM)" ] && { echo "Waiting for Plex to be claimed..."; tries=60; }
for _ in $(seq "$tries"); do
  grep -q 'PlexOnlineToken="' "$PREFS" 2>/dev/null && break
  sleep 5
done
if ! grep -q 'PlexOnlineToken="' "$PREFS" 2>/dev/null; then
  echo "Plex is not claimed yet. Get a token at https://plex.tv/claim, then:"
  echo "  sudo sed -i 's|^PLEX_CLAIM=.*|PLEX_CLAIM=claim-xxxx|' $STACK_DIR/.env"
  echo "  sudo bash $STACK_DIR/scripts/boot.sh && sudo bash $STACK_DIR/scripts/plex-setup.sh"
  exit 1
fi

set_pref() {  # set_pref KEY VALUE  (Plex must be stopped)
  if grep -q " $1=\"" "$PREFS"; then
    sed -i "s|\( $1=\"\)[^\"]*\"|\1$2\"|" "$PREFS"
  else
    sed -i "s|<Preferences |<Preferences $1=\"$2\" |" "$PREFS"
  fi
}

echo "Applying Plex settings..."
compose stop plex >/dev/null 2>&1
cp -p "$PREFS" "$PREFS.bak-$(date +%Y%m%d%H%M%S)"
set_pref PublishServerOnPlexOnlineKey 0                    # Remote Access off
set_pref RelayEnabled 0
set_pref GdmEnabled 0
set_pref LanNetworksBandwidth "$(envval LAN_SUBNET),$(envval PLEX_GATEWAY)/32"
set_pref customConnections "http://$LAN_IP:32400"
set_pref HardwareAcceleratedCodecs 1
set_pref TranscoderTempDirectory /transcode
set_pref autoEmptyTrash 0                                  # don't wipe the library if the mount drops
set_pref FSEventLibraryUpdatesEnabled 0                    # inotify doesn't work on FUSE
set_pref FSEventLibraryPartialScanEnabled 0
set_pref ScheduledLibraryUpdatesEnabled 1
set_pref ScheduledLibraryUpdateInterval 900
set_pref GenerateBIFBehavior never                         # these read whole files from Real-Debrid
set_pref GenerateChapterThumbBehavior never
set_pref GenerateIntroMarkerBehavior never
set_pref GenerateCreditsMarkerBehavior never
set_pref LoudnessAnalysisBehavior never
set_pref GenerateVADBehavior never
set_pref ButlerTaskDeepMediaAnalysis 0
sed -i 's| allowedNetworks="[^"]*"||' "$PREFS"             # never allow access without login
compose up -d plex >/dev/null 2>&1
# The PLEX_CLAIM token is single-use; drop it now that the server is claimed
sed -i 's|^PLEX_CLAIM=.*|PLEX_CLAIM=|' "$STACK_DIR/.env"

for _ in $(seq 40); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://$LAN_IP:32400/identity")" = 200 ] && break
  sleep 3
done

TOKEN=$(sed -n 's/.*PlexOnlineToken="\([^"]*\)".*/\1/p' "$PREFS")
api() { curl -s --max-time 30 -H "X-Plex-Token: $TOKEN" "$@"; }
existing=$(api "http://$LAN_IP:32400/library/sections")

add_library() {  # add_library NAME TYPE AGENT SCANNER PATH
  if echo "$existing" | grep -q "path=\"$5\""; then
    echo "  library '$1' already exists"
    return
  fi
  api -X POST -G "http://$LAN_IP:32400/library/sections" \
    --data-urlencode "name=$1" --data-urlencode "type=$2" --data-urlencode "agent=$3" \
    --data-urlencode "scanner=$4" --data-urlencode "language=$LANG_CODE" \
    --data-urlencode "location=$5" >/dev/null && echo "  library '$1' -> $5"
}

echo "Creating libraries ($LANG_CODE)..."
lib=${MNT#"$STACK_DIR"}   # /mnt/zurg or /mnt/torbox, as seen inside Plex
if [ "$PROVIDER" = torbox ]; then
  add_library Movies     movie tv.plex.agents.movie  "Plex Movie"     "$lib/movies"
  add_library "TV Shows" show  tv.plex.agents.series "Plex TV Series" "$lib/series"
else
  add_library Movies     movie tv.plex.agents.movie  "Plex Movie"     "$lib/movies"
  add_library "TV Shows" show  tv.plex.agents.series "Plex TV Series" "$lib/shows"
  add_library Anime      show  tv.plex.agents.series "Plex TV Series" "$lib/anime"
fi
echo "Plex is ready: http://$LAN_IP:32400/web"
