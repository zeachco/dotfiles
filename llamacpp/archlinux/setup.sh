#!/usr/bin/env bash
#
# All llama.cpp setup for Arch: install the router as a systemd --user service
# (WantedBy=default.target, so it comes back on every login) and point at the
# model fetch script if ~/models/light is empty.
#
# Skips itself when ~/dev/llama.cpp/build/bin/llama-server has not been built yet
# (see ryzen-llm-setup.md), so this is harmless on an Arch box without that setup.
#
# Invoked with a literal `bash`, NOT "$SHELL": utils.sh runs variant setup.sh files
# as `$SHELL <script>` and $SHELL is /bin/zsh on this box, so the shebang is
# ignored. install.sh uses `set -euo pipefail` plus ${BASH_SOURCE[0]}, and under
# zsh that resolves to the CALLER's cwd without aborting -- a silently wrong path,
# not an error.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"

# ---- hardware gate ------------------------------------------------------------
# Ryzen AI MAX only, mirroring the Apple Silicon gate on the macOS side. update.sh
# already self-gates and install.sh refuses to install a unit pointing at a binary
# that is not there, so this is belt-and-braces -- but it keeps the skip reason
# visible in the `dotfiles_update` output instead of silent no-ops, and stops a
# hand-built llama.cpp on some other Arch box from acquiring a router service it
# was never configured for. See llamacpp/shared/_hw-gate.sh.
. "$SCRIPT_DIR/../shared/_hw-gate.sh"

if ! is_ryzen_ai_max; then
  echo -e "\033[0;33mskipping\033[0m llama.cpp setup: no Ryzen AI MAX detected"
  exit 0
fi

# Same as the macOS side: name the stage so a no-op run is distinguishable from a
# step that never ran.
echo -e "\033[0;34mcheck \033[0mllama.cpp setup..."

# Pull llama.cpp and rebuild it when the build has fallen behind the checkout, BEFORE
# install.sh -- which refuses to install a unit pointing at a binary that is not there,
# so on a fresh box the build has to happen first for the router to be installed at all.
#
# Self-gating: it exits silently unless this is the Strix Halo + omarchy box. See the
# header there for why staleness is a stamp file and not an mtime.
bash "$SCRIPT_DIR/update.sh" ||
  echo -e "\033[0;31mllama.cpp update failed\033[0m"

# `|| echo` so a router failure does not abort the rest of the Arch setup.
bash "$SCRIPT_DIR/install.sh" ||
  echo -e "\033[0;31mllama router install failed\033[0m"

# Refresh pi's llamacpp* providers from the live routers. Only on the Strix Halo box
# -- the CPU half of that gate is the hardware gate at the top of this file, so only
# the omarchy half is left here: the providers point at THIS machine, and on any other
# host the routers are simply not there. Forgetting this step is how pi ended up listing a
# model set that no router served (2026-09-09: heavy tier had DeepSeek, pi did not).
if [[ -d /usr/share/omarchy ]]; then
  # install.sh may have just started a router; give /health a moment before syncing,
  # otherwise the sync warns "unreachable" and keeps the stale list.
  for port in 7070 7072; do
    for _ in $(seq 1 20); do
      curl -sf -m 2 "http://127.0.0.1:$port/health" >/dev/null 2>&1 && break
      sleep 1
    done
  done
  "$SCRIPT_DIR/../../bin/llamacpp-sync" ||
    echo -e "\033[0;33mllamacpp-sync failed; run it by hand once the routers are up\033[0m"
fi
