#!/usr/bin/env bash
#
# All vLLM setup for macOS: install vllm-metal with Homebrew and install the server
# as a launchd user agent. It downloads NO model. A model download is always an
# explicit `vllm-ctl fetch <id>`.
#
# vLLM runs beside llama.cpp, not in place of it. See vllm/README.md.
#
# Run this with a literal `bash`, not "$SHELL". See llamacpp/osx/setup.sh.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WARN="\033[0;33m"
FAIL="\033[0;31m"
INFO="\033[0;34m"
NORM="\033[0m"

TAP="vllm-project/vllm-metal"
TAP_URL="https://github.com/vllm-project/vllm-metal"
FORMULA="$TAP/vllm-metal"

# ---- hardware gate ------------------------------------------------------------
# Apple Silicon only: vllm-metal runs on MLX. Same gate as llama.cpp.
. "$SCRIPT_DIR/../../llamacpp/shared/_hw-gate.sh"

if ! is_apple_silicon; then
  echo -e "${WARN}skipping ${NORM}vLLM setup: not Apple Silicon"
  exit 0
fi

# The formula needs macOS 15 (Sequoia) or later.
if [[ "$(sw_vers -productVersion | cut -d. -f1)" -lt 15 ]]; then
  echo -e "${WARN}skipping ${NORM}vLLM setup: vllm-metal needs macOS 15 or later"
  exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
  echo -e "${WARN}skipping ${NORM}vLLM setup: brew is not installed"
  exit 0
fi

echo -e "${INFO}check ${NORM}vLLM setup..."

# ---- install vllm-metal ----------------------------------------------------------
# `brew list` and not `command -v vllm`: a `vllm` from an old venv on PATH must not
# hide a missing formula. Upgrades are not done here; run `brew upgrade vllm-metal`
# and then `vllm-ctl restart`.
if ! brew list vllm-metal >/dev/null 2>&1; then
  echo -e "${WARN}installing ${NORM}vllm-metal (Homebrew, private Python 3.12 venv)..."

  if ! brew tap | grep -qx "$TAP"; then
    brew tap "$TAP" "$TAP_URL" ||
      echo -e "${FAIL}brew tap $TAP failed${NORM}"
  fi

  # Homebrew refuses to load a formula from an untrusted tap. Trust this ONE formula,
  # not the full tap: a formula that the tap adds later stays untrusted.
  # An older Homebrew has no `trust` command and does not need it.
  if brew commands --quiet 2>/dev/null | grep -qx trust; then
    brew trust --formula "$FORMULA" >/dev/null ||
      echo -e "${FAIL}brew trust $FORMULA failed${NORM}"
  fi

  brew install "$FORMULA" ||
    echo -e "${FAIL}vllm-metal install failed${NORM}"
fi

# `|| echo` so a failure here does not stop the rest of the macOS setup.
bash "$SCRIPT_DIR/install.sh" ||
  echo -e "${FAIL}vllm agent install failed${NORM}"
