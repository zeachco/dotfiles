#!/usr/bin/env bash
# Initial Qwen + GLM download, also runnable manually to resume after a failure.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_fetch-lib.sh"

main() {
  local models="$HOME/models/light" qwen_id=qwen3.8 projector=mmproj-F16.gguf
  if [[ "$(uname -s)" == Darwin ]]; then
    models="${LOS_MODELS_DIR:-$HOME/models}"
    qwen_id=Qwen3.8-27B
    projector=mmproj-BF16.gguf
  fi

  # Stage outside the router's model directory: a partial GGUF must not be served
  # or mistaken by fetch_dir_model for an already complete model on a retry.
  local staging="$HOME/models/.initial-downloads/$qwen_id"
  local target="$models/$qwen_id"
  mkdir -p "$models" || return 1
  if [[ -e "$target" || -L "$target" ]]; then
    echo "Qwen: existing $target left untouched"
  else
    if fetch unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-Q4_K_M.gguf "$staging" &&
       fetch unsloth/Qwen3.8-27B-GGUF "$projector" "$staging"; then
      mv "$staging" "$target" || return 1
    fi
  fi

  staging="$HOME/models/.initial-downloads/glm"
  target="$models/GLM-4.7-Flash-UD-Q4_K_XL.gguf"
  if [[ -e "$target" || -L "$target" ]]; then
    echo "GLM: existing $target left untouched"
  elif fetch unsloth/GLM-4.7-Flash-GGUF GLM-4.7-Flash-UD-Q4_K_XL.gguf "$staging"; then
    mv "$staging/GLM-4.7-Flash-UD-Q4_K_XL.gguf" "$target" || return 1
  fi
  fetch_report
}

echo "Initial model downloads started: $(date)"
if main; then
  echo "Initial model downloads complete: $(date)"
  echo "Restart your llama.cpp router and run llamacpp-sync to refresh clients."
else
  echo "Initial model downloads failed: $(date)"
  echo "Resume with: bash $SCRIPT_DIR/fetch-initial-models.sh"
  exit 1
fi
