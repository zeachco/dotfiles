#!/usr/bin/env bash
#
# Install the llama.cpp routers as systemd --user services:
#   llama-router.service        light tier, :7070, LAN-reachable
#   llama-router-cheap.service  cheap tier, :7071, loopback only
#   llama-router-heavy.service  heavy tier, :7072, LAN-reachable, one model, no autoload
#
# The cheap tier is an isolation boundary, not a performance tier -- it keeps
# high-frequency shell traffic off the light router, whose eviction is pure LRU
# with no way to pin a model. See llamacpp/archlinux/cheap.ini for the argument.
#
# Mirrors llamacpp/osx/install.sh: guard, render the template, cmp -s it
# against what is already installed, and skip BEFORE touching the running service
# when nothing changed. Re-running on every `dotfiles_update` is a no-op.
#
# Invoke this with `bash`, not "$SHELL" -- utils.sh runs variant setup scripts as
# `$SHELL <script>`, and under zsh with `set -u`, ${BASH_SOURCE[0]} is unset: the
# SCRIPT_DIR idiom below would print a diagnostic and silently resolve to the
# CALLER's cwd instead of aborting.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
USER_UNIT_DIR="$HOME/.config/systemd/user"

# ---- guard: never install a unit pointing at a binary that is not there -----------
# The units themselves use %h (systemd's own specifier), so this checks the same path
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

# ---- knobs -------------------------------------------------------------------------
_require_percent() { # name value
  if ! [[ "$2" =~ ^[0-9]+$ ]] || (($2 < 1 || $2 > 100)); then
    echo "llama router: $1 must be an integer percent from 1-100, got '$2'" >&2
    exit 1
  fi
}
_require_positive() { # name value
  if ! [[ "$2" =~ ^[0-9]+$ ]] || (($2 < 1)); then
    echo "llama router: $1 must be a positive integer, got '$2'" >&2
    exit 1
  fi
}

# Light tier. Default 90%: leaves headroom for the rest of the desktop during
# CPU-side work (warmup, tokenization, prompt processing that spills off the GPU).
CPU_QUOTA="${LOS_CPU_QUOTA:-90}"
_require_percent LOS_CPU_QUOTA "$CPU_QUOTA"

# Default half the machine's cores, same "leave headroom" reasoning as CPUQuota
# above -- this caps ggml's own thread pool, CPUQuota caps the cgroup as a whole.
HALF_CORES=$(($(nproc) / 2))
((HALF_CORES < 1)) && HALF_CORES=1
THREADS="${LOS_THREADS:-$HALF_CORES}"
_require_positive LOS_THREADS "$THREADS"

# Cheap tier: deliberately small on both axes. A tab-title summary must never
# compete with interactive generation on :7070, and nothing here is latency-critical.
CHEAP_CPU_QUOTA="${LOS_CHEAP_CPU_QUOTA:-25}"
_require_percent LOS_CHEAP_CPU_QUOTA "$CHEAP_CPU_QUOTA"
CHEAP_THREADS="${LOS_CHEAP_THREADS:-4}"
_require_positive LOS_CHEAP_THREADS "$CHEAP_THREADS"

# Heavy tier: same headroom defaults as the light tier. One model, no autoload -- the
# quota only matters during a deliberate load and the session that follows.
HEAVY_CPU_QUOTA="${LOS_HEAVY_CPU_QUOTA:-90}"
_require_percent LOS_HEAVY_CPU_QUOTA "$HEAVY_CPU_QUOTA"
HEAVY_THREADS="${LOS_HEAVY_THREADS:-$HALF_CORES}"
_require_positive LOS_HEAVY_THREADS "$HEAVY_THREADS"

# ---- directories the units depend on -----------------------------------------------
# Per-tier LLAMA_CACHE is load-bearing, not tidy: cached models are enumerated
# unconditionally and ahead of --models-dir, so a shared cache would leak the light
# tier's models into the cheap router.
mkdir -p \
  "$HOME/models/light" \
  "$HOME/models/cheap" \
  "$HOME/models/heavy" \
  "$HOME/.cache/llama.cpp-light" \
  "$HOME/.cache/llama.cpp-cheap" \
  "$HOME/.cache/llama.cpp-heavy" \
  "$USER_UNIT_DIR"

# ---- render + install one unit ------------------------------------------------------
# One scratch dir for every render, cleaned up on any exit -- including the error
# paths below, which `exit` rather than return.
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Sets CHANGED=1 when it actually wrote something, so daemon-reload runs at most once.
CHANGED=0
install_unit() { # unit-name, then sed -e expressions
  local unit="$1"; shift
  local template="$SCRIPT_DIR/$unit"
  local installed="$USER_UNIT_DIR/$unit"
  local rendered="$WORK_DIR/$unit"

  if [[ ! -f "$template" ]]; then
    echo "llama router: missing template $template" >&2
    exit 1
  fi

  sed "$@" "$template" >"$rendered"

  if grep -q '@[A-Z_]*@' "$rendered"; then
    echo "llama router: unsubstituted token left in $unit:" >&2
    grep -n '@[A-Z_]*@' "$rendered" >&2
    exit 1
  fi

  # Idempotence: bail out before touching the running service.
  if [[ -f "$installed" ]] \
    && cmp -s "$rendered" "$installed" \
    && systemctl --user is-active --quiet "$unit"; then
    echo "llama router: $unit is already installed and running"
    return 0
  fi

  install -m 644 "$rendered" "$installed"
  CHANGED=1
  echo "llama router: installed $unit"
}

install_unit "llama-router.service" \
  -e "s|@CPU_QUOTA@|$CPU_QUOTA|g" \
  -e "s|@THREADS@|$THREADS|g"

install_unit "llama-router-cheap.service" \
  -e "s|@CHEAP_CPU_QUOTA@|$CHEAP_CPU_QUOTA|g" \
  -e "s|@CHEAP_THREADS@|$CHEAP_THREADS|g"

install_unit "llama-router-heavy.service" \
  -e "s|@HEAVY_CPU_QUOTA@|$HEAVY_CPU_QUOTA|g" \
  -e "s|@HEAVY_THREADS@|$HEAVY_THREADS|g"

if ((CHANGED)); then
  systemctl --user daemon-reload
fi

# enable --now is idempotent and cheap; it also recovers a unit that was installed
# on a previous run but has since been stopped or disabled.
systemctl --user enable --now "llama-router.service"
systemctl --user enable --now "llama-router-cheap.service"
systemctl --user enable --now "llama-router-heavy.service"

echo "llama router: light tier -> http://localhost:7070 (CPUQuota=${CPU_QUOTA}%, threads=${THREADS})"
echo "llama router: cheap tier -> http://127.0.0.1:7071 (CPUQuota=${CHEAP_CPU_QUOTA}%, threads=${CHEAP_THREADS})"
echo "llama router: heavy tier -> http://localhost:7072 (CPUQuota=${HEAVY_CPU_QUOTA}%, threads=${HEAVY_THREADS}, loads on request only)"
# A changed unit is installed but NOT restarted: enable --now is a no-op for a running
# unit, and a restart drops in-flight generation. Say so instead of doing it.
for u in llama-router.service llama-router-cheap.service llama-router-heavy.service; do
  systemctl --user is-active --quiet "$u" || continue
  started="$(systemctl --user show -p ExecMainStartTimestamp --value "$u" 2>/dev/null)"
  [[ -n "$started" ]] || continue
  if (( $(date -d "$started" +%s 2>/dev/null || echo 0) < $(stat -c %Y "$USER_UNIT_DIR/$u") )); then
    echo "llama router: $u changed since it started -- restart when idle: systemctl --user restart $u"
  fi
done
echo "llama router: logs with: journalctl --user -u llama-router.service -f"

if [[ -z "$(ls -A "$HOME/models/light" 2>/dev/null || true)" ]]; then
  echo "llama router: ~/models/light is empty. Fetch the model set with:"
  echo "              bash ${DOT_DIR:-$HOME/dotfiles}/llamacpp/archlinux/fetch-models.sh"
fi

if [[ -z "$(ls -A "$HOME/models/cheap" 2>/dev/null || true)" ]]; then
  echo "llama router: ~/models/cheap is empty. The cheap tier expects a small model, e.g."
  echo "              mkdir -p ~/models/cheap/gemma-4-E2B-it && ln -s \\"
  echo "                ~/models/light/gemma-4-E2B-it-GGUF/gemma-4-E2B-it-Q4_K_M.gguf \\"
  echo "                ~/models/cheap/gemma-4-E2B-it/"
  echo "              (symlink, not a copy; the mmproj is deliberately left out -- see cheap.ini)"
fi
