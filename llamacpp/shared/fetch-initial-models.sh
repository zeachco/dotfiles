#!/usr/bin/env bash
# Initial Qwen download (+ GLM on the Mac), also runnable manually to resume after a failure.
# On the Arch box a first install goes through bin/llamacpp-fetch-missing's fzf picker
# instead (clone.sh no longer launches this there); this stays the Mac's unattended path.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_fetch-lib.sh"

main() {
  local models="$HOME/models/llama" qwen_id=qwen3.8 projector=mmproj-F16.gguf
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

  # Mac only: on the Arch box GLM-4.7-Flash is part of fetch-models.sh (loaded on
  # purpose, never on its own) rather than the initial download.
  if [[ "$(uname -s)" == Darwin ]]; then
    staging="$HOME/models/.initial-downloads/glm"
    target="$models/GLM-4.7-Flash-UD-Q4_K_XL.gguf"
    if [[ -e "$target" || -L "$target" ]]; then
      echo "GLM: existing $target left untouched"
    elif fetch unsloth/GLM-4.7-Flash-GGUF GLM-4.7-Flash-UD-Q4_K_XL.gguf "$staging"; then
      mv "$staging/GLM-4.7-Flash-UD-Q4_K_XL.gguf" "$target" || return 1
      # Only the file moved; its digest row has to follow for verification to find it.
      provenance_move "$staging" "$models" GLM-4.7-Flash-UD-Q4_K_XL.gguf
    fi
  fi

  # Arch only: the shell helpers' summarize/tab_autoname model (_ai_tools.sh). 2.9 +
  # 0.9 GB, so it costs the initial download almost nothing. The Mac gets it from
  # fetch-models-osx.sh.
  if [[ "$(uname -s)" != Darwin ]]; then
    staging="$HOME/models/.initial-downloads/gemma-4-E2B-it-GGUF"
    target="$models/gemma-4-E2B-it-GGUF"
    if [[ -e "$target" || -L "$target" ]]; then
      echo "gemma-4-E2B: existing $target left untouched"
    elif fetch unsloth/gemma-4-E2B-it-GGUF gemma-4-E2B-it-Q4_K_M.gguf "$staging" &&
         fetch unsloth/gemma-4-E2B-it-GGUF mmproj-F16.gguf "$staging"; then
      mv "$staging" "$target" || return 1
    fi
  fi

  # Bytes are proven before anything is served: sha256 of every download against the
  # digest HF returned, then a live rescan on the router -- a reload, not a restart, so
  # a fresh install needs no manual step afterwards.
  fetch_verify "$models"
  routers_reload 7070
  fetch_report
}

echo "Initial model downloads started: $(date)"
if main; then
  echo "Initial model downloads complete and verified: $(date)"
  echo "The router was asked to reload; run llamacpp-sync to refresh clients (and los to load)."
else
  echo "Initial model downloads failed or did not verify: $(date)"
  echo "Resume with: bash $SCRIPT_DIR/fetch-initial-models.sh"
  exit 1
fi
