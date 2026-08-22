#!/usr/bin/env bash

set -euo pipefail

USER_UNIT_DIR="$HOME/.config/systemd/user"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/framework-rgb/Cargo.toml"

if ! command -v framework_tool >/dev/null 2>&1; then
  echo "Framework RGB daemon skipped: framework-tools is not installed"
  exit 0
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "Framework RGB daemon skipped: cargo is not installed"
  exit 0
fi

if ! command -v pkexec >/dev/null 2>&1; then
  echo "Framework RGB daemon skipped: pkexec is not installed"
  exit 0
fi

echo "Framework RGB: building Rust daemon..."
cargo build --release --locked --manifest-path "$MANIFEST"

# Stop and unregister the legacy user daemons before installing the system daemon.
systemctl --user disable --now \
  ollama-framework-rgb.service \
  llamacpp-framework-rgb.service \
  framework-rgb.service 2>/dev/null || true
rm -f \
  "$USER_UNIT_DIR/ollama-framework-rgb.service" \
  "$USER_UNIT_DIR/llamacpp-framework-rgb.service" \
  "$USER_UNIT_DIR/framework-rgb.service"
systemctl --user daemon-reload

echo "Framework RGB: installing privileged system daemon..."
pkexec "$SCRIPT_DIR/install-root.sh" "$USER"
echo "Framework RGB: enabled and started framework-rgb@$USER.service"
