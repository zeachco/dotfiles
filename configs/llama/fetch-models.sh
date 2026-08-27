#!/usr/bin/env bash
# Fetch the model set into the router's tier directories. Resumable: rerun to continue
# an interrupted download (curl -C -). Safe to run while the router is up; new models
# are picked up on the next router restart.
#
# Layout notes:
#   - single-file models sit at the top level of a tier dir; the id is the filename stem
#   - draft models live OUTSIDE the tier dirs, in ~/models/drafts, so the directory
#     scanner doesn't try to pair them with a model as a shard/projector
set -uo pipefail

# fetch()/hf_ls()/fetch_report() live in _fetch-lib.sh, shared with
# fetch-models-osx.sh. The shared version adds a size pre-check: `curl -C -` on an
# already-complete file makes the CDN answer 416, which --fail turns into a non-zero
# exit, so the old inline fetch() reported every finished model as FAILED on a re-run.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$SCRIPT_DIR/_fetch-lib.sh"

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
# 87.3 GiB. Qwen3.8-Flash-Next: 125B + 51B n-gram embedding, 6B active. Three shards
# MUST share one subdirectory -- the scanner reads a dir as one multi-shard model and
# the dir name is the id. UD-IQ4_XS over UD-Q4_K_XL (103.7 GiB), same call as
# Coder-Next: the bigger quant does not share the tier. The GGUF declares the
# qwen4exp arch, which needs llama.cpp PR #27742 (unsloth) -- rebuild before first load.
fetch unsloth/Qwen3.8-Flash-Next-GGUF UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf "$HOME/models/light/Qwen3.8-Flash-Next"
fetch unsloth/Qwen3.8-Flash-Next-GGUF UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00002-of-00003.gguf "$HOME/models/light/Qwen3.8-Flash-Next"
fetch unsloth/Qwen3.8-Flash-Next-GGUF UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00003-of-00003.gguf "$HOME/models/light/Qwen3.8-Flash-Next"

echo
echo "Done. Restart the router to pick up new models:"
echo "  systemctl --user restart llama-router   # or: killport 8080 && los"

# Non-zero exit if any download failed, so a 404'd filename cannot pass as success.
fetch_report
