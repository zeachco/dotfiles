#!/usr/bin/env bash

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Framework RGB installation must run as root" >&2
  exit 1
fi

ROUTER_USER="${1:?router user is required}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SERVICE="framework-rgb@$ROUTER_USER.service"

systemctl disable --now "$SERVICE" 2>/dev/null || true
install -Dm755 \
  "$SCRIPT_DIR/framework-rgb/target/release/framework-rgb" \
  /usr/local/bin/framework-rgb
install -Dm644 \
  "$SCRIPT_DIR/framework-rgb@.service" \
  /etc/systemd/system/framework-rgb@.service

systemctl daemon-reload
systemctl enable --now "$SERVICE"
