#!/usr/bin/env bash

set -u

SERVICE_NAME="llamacpp-framework-rgb.service"
OLD_SERVICE_NAME="ollama-framework-rgb.service"
USER_UNIT_DIR="$HOME/.config/systemd/user"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v framework_tool >/dev/null 2>&1; then
  echo "Framework RGB daemon skipped: framework-tools is not installed"
  exit 0
fi

mkdir -p "$USER_UNIT_DIR"

# Stop and unregister the old Ollama monitor plus any currently installed copy
# before installing this unit, making repeated setup runs deterministic.
systemctl --user disable --now "$OLD_SERVICE_NAME" "$SERVICE_NAME" 2>/dev/null || true
rm -f "$USER_UNIT_DIR/$OLD_SERVICE_NAME"
install -m 0644 "$SCRIPT_DIR/$SERVICE_NAME" "$USER_UNIT_DIR/$SERVICE_NAME"

systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE_NAME"
