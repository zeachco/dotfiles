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


echo "Framework RGB: building Rust daemon..."
cargo build --release --locked --manifest-path "$MANIFEST"

BUILT_BINARY="$SCRIPT_DIR/framework-rgb/target/release/framework-rgb"
INSTALLED_BINARY="/usr/local/bin/framework-rgb"
INSTALLED_UNIT="/etc/systemd/system/framework-rgb@.service"

# Cargo performs its own incremental build check. Avoid privilege escalation and
# a service restart when the resulting executable and unit are already installed.
if [[ -x "$INSTALLED_BINARY" ]] \
  && cmp -s "$BUILT_BINARY" "$INSTALLED_BINARY" \
  && cmp -s "$SCRIPT_DIR/framework-rgb@.service" "$INSTALLED_UNIT"; then
  echo "Framework RGB: installed binary and service are already up to date"
  exit 0
fi

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
sudo "$SCRIPT_DIR/install-root.sh" "$USER"
echo "Framework RGB: enabled and started framework-rgb@$USER.service"
