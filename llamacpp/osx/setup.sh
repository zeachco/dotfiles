#!/usr/bin/env bash
#
# All llama.cpp setup for macOS: brew-install llama.cpp, install the router as a
# launchd user agent (Aqua session, so it comes back on every GUI login), and
# optionally fetch the model set.
#
# Invoked with a literal `bash`, NOT "$SHELL": utils.sh runs variant setup.sh files
# as `$SHELL <script>` and $SHELL is /bin/zsh here, so the shebang is ignored.
# install.sh uses `set -euo pipefail` plus ${BASH_SOURCE[0]}, and under zsh that
# resolves to the CALLER's cwd without aborting -- a silently wrong path, not an
# error.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WARN="\033[0;33m"
FAIL="\033[0;31m"
NORM="\033[0m"

# llama.cpp, used in router mode by the com.zeachco.llama-router launchd agent
# below. The brew formula depends on `ggml`, which on Apple Silicon is built with
# GGML_METAL=ON (only Intel macOS gets METAL=OFF) and GGML_BACKEND_DL=ON, with the
# backends dlopen'd from $(brew --prefix)/opt/ggml/libexec -- so this is a
# Metal-accelerated build with no source compile needed.
#
# Checked with `brew list` rather than `needs llama-server`: v0.3.0 ships both a
# multi-tool `llama` and per-subcommand `llama-*` binaries, so a binary-name probe
# is fragile across upgrades.
if ! brew list llama.cpp >/dev/null 2>&1; then
  echo -e "${WARN}installing ${NORM}llama.cpp..."
  brew install llama.cpp
fi

# `|| echo` so a router failure does not abort the rest of the macOS setup.
bash "$SCRIPT_DIR/install.sh" ||
  echo -e "${FAIL}llama router install failed${NORM}"

# The model set (~29 GB) is NOT fetched here by default. install_profile runs this
# file on every `dotfiles_update`, there is no consent step anywhere in the setup
# flow, and the router does not need models to start -- verifying it boots and
# answers /health with an empty ~/models is a better first milestone than a 29 GB
# download.
if [[ "${LOS_FETCH_MODELS:-}" == "1" ]]; then
  bash "$SCRIPT_DIR/fetch-models-osx.sh" ||
    echo -e "${FAIL}llama model fetch failed${NORM}"
fi
