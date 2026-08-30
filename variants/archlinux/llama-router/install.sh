#!/usr/bin/env bash
#
# Install the llama.cpp router (light tier) as a systemd --user service.
#
# Mirrors variants/osx/llama-router/install.sh: guard, render the template, cmp -s it
# against what is already installed, and exit 0 BEFORE touching the running service
# when nothing changed. Re-running on every `dotfiles_update` is a no-op.
#
# Invoke this with `bash`, not "$SHELL" -- utils.sh runs variant setup scripts as
# `$SHELL <script>`, and under zsh with `set -u`, ${BASH_SOURCE[0]} is unset: the
# SCRIPT_DIR idiom below would print a diagnostic and silently resolve to the
# CALLER's cwd instead of aborting.

set -euo pipefail

UNIT="llama-router.service"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/$UNIT"
USER_UNIT_DIR="$HOME/.config/systemd/user"
INSTALLED="$USER_UNIT_DIR/$UNIT"

# ---- guard: never install a unit pointing at a binary that is not there -----------
# The unit itself uses %h (systemd's own specifier), so this checks the same path
# the rendered ExecStart will use without needing to substitute it.
if [[ ! -x "$HOME/dev/llama.cpp/build/bin/llama-server" ]]; then
  echo "llama router skipped: llama-server not built at $HOME/dev/llama.cpp/build/bin/llama-server"
  echo "                      (see ryzen-llm-setup.md for the build steps)"
  exit 0
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "llama router skipped: systemctl is not available"
  exit 0
fi

# Default 90%: leaves headroom for the rest of the desktop during CPU-side work
# (warmup, tokenization, prompt processing that spills off the GPU). Override with
# LOS_CPU_QUOTA=<percent> bash install.sh, or edit the installed unit afterwards.
CPU_QUOTA="${LOS_CPU_QUOTA:-90}"
if ! [[ "$CPU_QUOTA" =~ ^[0-9]+$ ]] || ((CPU_QUOTA < 1 || CPU_QUOTA > 100)); then
  echo "llama router: LOS_CPU_QUOTA must be an integer percent from 1-100, got '$CPU_QUOTA'" >&2
  exit 1
fi

# Default half the machine's cores, same "leave headroom" reasoning as CPUQuota
# above -- this caps ggml's own thread pool, CPUQuota caps the cgroup as a whole.
# Override with LOS_THREADS=<n> bash install.sh.
HALF_CORES=$(($(nproc) / 2))
((HALF_CORES < 1)) && HALF_CORES=1
THREADS="${LOS_THREADS:-$HALF_CORES}"
if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || ((THREADS < 1)); then
  echo "llama router: LOS_THREADS must be a positive integer, got '$THREADS'" >&2
  exit 1
fi

# ---- directories the unit depends on ----------------------------------------------
mkdir -p \
  "$HOME/models/light" \
  "$HOME/.cache/llama.cpp-light" \
  "$USER_UNIT_DIR"

# ---- render ------------------------------------------------------------------------
RENDERED="$(mktemp)"
trap 'rm -f "$RENDERED"' EXIT

sed \
  -e "s|@CPU_QUOTA@|$CPU_QUOTA|g" \
  -e "s|@THREADS@|$THREADS|g" \
  "$TEMPLATE" >"$RENDERED"

if grep -q '@[A-Z_]*@' "$RENDERED"; then
  echo "llama router: unsubstituted token left in the unit:" >&2
  grep -n '@[A-Z_]*@' "$RENDERED" >&2
  exit 1
fi

# ---- idempotence: bail out before touching the running service --------------------
if [[ -f "$INSTALLED" ]] \
  && cmp -s "$RENDERED" "$INSTALLED" \
  && systemctl --user is-active --quiet "$UNIT"; then
  echo "llama router: unit is already installed and running (CPUQuota=${CPU_QUOTA}%, threads=${THREADS})"
  exit 0
fi

install -m 644 "$RENDERED" "$INSTALLED"

systemctl --user daemon-reload
systemctl --user enable --now "$UNIT"

echo "llama router: installed and started $UNIT -> http://localhost:8080 (CPUQuota=${CPU_QUOTA}%, threads=${THREADS})"
echo "llama router: logs with: journalctl --user -u $UNIT -f"

if [[ -z "$(ls -A "$HOME/models/light" 2>/dev/null || true)" ]]; then
  echo "llama router: ~/models/light is empty. Fetch the model set with:"
  echo "              bash ${DOT_DIR:-$HOME/dotfiles}/configs/llama/fetch-models.sh"
fi
