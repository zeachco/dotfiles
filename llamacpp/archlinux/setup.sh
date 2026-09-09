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
