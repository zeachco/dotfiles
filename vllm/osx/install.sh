#!/usr/bin/env bash
#
# Install the vLLM server as a launchd USER AGENT (com.zeachco.vllm).
#
# Same contract as llamacpp/osx/install.sh: render the plist, compare it with the
# installed file, and exit before touching the running service if nothing changed.
# A `dotfiles_update` with no change does not restart the server.
#
# Run this with `bash`, not `$SHELL`. See llamacpp/osx/install.sh for the reason.
# macOS has bash 3.2: no associative arrays, no mapfile, no ${var,,}.

set -euo pipefail

LABEL="com.zeachco.vllm"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/$LABEL.plist"
AGENT_DIR="$HOME/Library/LaunchAgents"
INSTALLED="$AGENT_DIR/$LABEL.plist"
DOMAIN="gui/$(id -u)"
DOT_DIR="${DOT_DIR:-$HOME/dotfiles}"

# ---- guards: no agent without a binary -------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  echo "vllm skipped: brew is not installed"
  exit 0
fi
BREW="$(brew --prefix)"

if [[ ! -x "$BREW/bin/vllm" ]]; then
  echo "vllm skipped: $BREW/bin/vllm is not installed"
  echo "              install: bash $DOT_DIR/vllm/osx/setup.sh"
  exit 0
fi

# launchd refuses to start a job if WorkingDirectory or the log directory is missing.
mkdir -p "$HOME/Library/Logs/vllm" "$AGENT_DIR"

# ---- render ----------------------------------------------------------------------
RENDERED="$(mktemp -t vllm-plist)"
trap 'rm -f "$RENDERED"' EXIT

sed \
  -e "s|@HOME@|$HOME|g" \
  -e "s|@BREW@|$BREW|g" \
  -e "s|@DOT_DIR@|$DOT_DIR|g" \
  "$TEMPLATE" >"$RENDERED"

if ! plutil -lint "$RENDERED" >/dev/null; then
  echo "vllm: rendered plist failed plutil -lint" >&2
  exit 1
fi
if grep -q '<string>[^<]*@[A-Z_]*@' "$RENDERED"; then
  echo "vllm: unsubstituted token left in the plist:" >&2
  grep -n '<string>[^<]*@[A-Z_]*@' "$RENDERED" >&2
  exit 1
fi

# ---- idempotence -----------------------------------------------------------------
# Both conditions matter: an identical file that is not loaded must be bootstrapped.
if [[ -f "$INSTALLED" ]] &&
  cmp -s "$RENDERED" "$INSTALLED" &&
  launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
  echo "vllm: agent is already installed and loaded"
  exit 0
fi

# bootout of a label that was never loaded exits 113. That is the first-run path.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

# /usr/bin/install, not bare `install`: the dotfiles define install() as a package helper.
/usr/bin/install -m 644 "$RENDERED" "$INSTALLED"
launchctl bootstrap "$DOMAIN" "$INSTALLED"

echo "vllm: bootstrapped $LABEL (idle until: vllm-ctl use <id>)"
echo "vllm: logs at ~/Library/Logs/vllm/server.log (launchd does not rotate them)"
