#!/bin/bash
# Start the stack again after scripts/stop.sh (or any time it should be running).
#   sudo bash scripts/start.sh
. "$(dirname "$0")/common.sh"
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }

rm -f "$STACK_DIR/STOPPED"
log "start: starting the stack"
bash "$STACK_DIR/scripts/boot.sh"
compose ps --format '{{.Name}}: {{.Status}}' 2>/dev/null || compose ps
