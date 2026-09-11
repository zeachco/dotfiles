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
INFO="\033[0;34m"
NORM="\033[0m"

# ---- hardware gate ------------------------------------------------------------
# Apple Silicon only. On an Intel Mac the brew formula builds ggml with
# GGML_METAL=OFF, so the router would run a CPU-only llama.cpp behind a launchd
# agent that never gets used -- and osx.ini's memory budget is sized for unified
# memory that an Intel box does not have. See llamacpp/shared/_hw-gate.sh.
. "$SCRIPT_DIR/../shared/_hw-gate.sh"

if ! is_apple_silicon; then
  echo -e "${WARN}skipping ${NORM}llama.cpp setup: not Apple Silicon"
  exit 0
fi

# Announce the stage. Everything below is idempotent and says nothing on a box where
# it is all already in place, so without this line a `dotfiles_update` gives no sign
# the llama.cpp step ran at all -- which reads as "it never fired".
echo -e "${INFO}check ${NORM}llama.cpp setup..."

# ---- build deps for the source build ---------------------------------------------
# update.sh preflights these too and prints the same brew command; installing them
# here means the first `dotfiles_update` on a fresh Mac does not need a second run.
if ! command -v cmake >/dev/null 2>&1; then
  echo -e "${WARN}installing ${NORM}cmake (llama.cpp build dep)..."
  brew install cmake
fi

# ---- track master from source ----------------------------------------------------
# Clone/fast-forward ~/dev/llama.cpp and rebuild when the build has fallen behind the
# checkout, BEFORE install.sh -- which picks the source build over the brew one when
# it exists, so on a fresh box the build has to happen first for the router to point
# at it at all. Self-gating and idempotent: a current build exits in seconds.
#
# This also makes the shared launchers work here. llamacpp/shared/_llama.sh hardcodes
# LLAMA_CPP_BUILD=$HOME/dev/llama.cpp/build, so `los-server-light` and friends were
# Arch-only until now.
bash "$SCRIPT_DIR/update.sh" ||
  echo -e "${FAIL}llama.cpp update failed${NORM}"

# ---- brew llama.cpp: the fallback ------------------------------------------------
# Only when the source build is absent -- a failed/skipped build, or a first run that
# has not finished cloning yet. The formula depends on `ggml`, which on Apple Silicon
# is built with GGML_METAL=ON (only Intel macOS gets METAL=OFF) and
# GGML_BACKEND_DL=ON, with the backends dlopen'd from $(brew --prefix)/opt/ggml/libexec
# -- so it is Metal-accelerated, just weeks behind master.
#
# Checked with `brew list` rather than `needs llama-server`: v0.3.0 ships both a
# multi-tool `llama` and per-subcommand `llama-*` binaries, so a binary-name probe is
# fragile across upgrades.
if [[ ! -x "${LLAMA_CPP_BUILD:-$HOME/dev/llama.cpp/build}/bin/llama-server" ]] \
  && ! brew list llama.cpp >/dev/null 2>&1; then
  echo -e "${WARN}installing ${NORM}llama.cpp (brew fallback, no source build yet)..."
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
