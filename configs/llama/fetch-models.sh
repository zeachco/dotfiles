#!/usr/bin/bash
# Fetch the model set into the router's tier directories. Resumable: rerun to continue
# an interrupted download (curl -C -). Safe to run while the router is up; new models
# are picked up on the next router restart.
#
# Layout notes:
#   - single-file models sit at the top level of a tier dir; the id is the filename stem
#   - draft models live OUTSIDE the tier dirs, in ~/models/drafts, so the directory
#     scanner doesn't try to pair them with a model as a shard/projector
set -uo pipefail

HF=https://huggingface.co

fetch() { # repo file destdir
  local repo="$1" file="$2" dest="$3"
  local out="$dest/${file##*/}"
  mkdir -p "$dest"
  echo "==> $repo :: ${file##*/}"
  curl -L --fail --retry 10 --retry-delay 5 --retry-all-errors -C - \
    --progress-bar -o "$out" "$HF/$repo/resolve/main/$file" || {
    echo "FAILED: $repo/$file" >&2
    return 1
  }
}

# --- heavy tier: one at a time -------------------------------------------------
# 63.4 GB. Workhorse: best capability-per-token-rate on this box (~55 t/s).
fetch ggml-org/gpt-oss-120b-GGUF gpt-oss-120b-MXFP4.gguf "$HOME/models/heavy"
# 0.8 GB EAGLE3 draft for the above -> spec-type = draft-eagle3 in heavy.ini.
fetch ggml-org/gpt-oss-120b-GGUF eagle3-gpt-oss-120b-Q8_0.gguf "$HOME/models/drafts"

# --- light tier: several coexist -----------------------------------------------
# 38.4 GB. Loop engine: 80B total / 3B active, 70.6% SWE-bench Verified.
# UD-Q4_K_XL is the higher-quality quant but 49.6 GB, too big to share the tier.
fetch unsloth/Qwen3-Coder-Next-GGUF Qwen3-Coder-Next-UD-IQ4_XS.gguf "$HOME/models/light"
# 17.5 GB. Fan-out: cheap parallel subagents and quick tool calls.
fetch unsloth/GLM-4.7-Flash-GGUF GLM-4.7-Flash-UD-Q4_K_XL.gguf "$HOME/models/light"

echo
echo "Done. Restart the router to pick up new models:"
echo "  systemctl --user restart llama-router   # or: killport 8080 && los"
