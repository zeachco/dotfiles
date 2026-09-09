#!/usr/bin/env bash
# Fetch the model set into the router's tier directories. Resumable: rerun to continue
# an interrupted download (curl -C -). New models are picked up on the next router
# restart, or immediately with `curl -s 'localhost:7070/v1/models?reload=1'`.
#
# Mostly safe to run while the router is up, with one caveat: a local file whose size
# differs from upstream gets OVERWRITTEN IN PLACE (same inode), and the log says so.
# Models loaded with -ngl 999 have already released their file mapping and are fine;
# unload anything CPU-resident or partially offloaded before overwriting it.
#
# EVERY GGUF UNDER ~/models SHOULD HAVE A LINE HERE. It did not used to: qwen3.8 -- the
# default model for every agent -- existed only as a hardlink out of ollama's blob
# store, so retiring ollama would have left no way to re-obtain it. `bin/llamacpp-audit`
# now checks this invariant; keep it true.
#
# THE ONE EXCEPTION, and it cannot be fixed:
#   ~/models/heavy/DeepSeek-V4-Flash-chat-v2/DeepSeek-V4-Flash-Layers37-42Q4KExperts-…
#   -imatrix-fixed.gguf  (90.89 GiB)
# is a hand-tuned mixed quant (layers 37-42 experts Q4_K, other expert layers IQ2_XXS
# gate/up, Q2_K down, attn-proj/shared-experts/output Q8) built against a custom
# imatrix. It is not a published artifact and there is no recipe that reproduces it.
# It is the only file on this box a disk failure would lose permanently -- back it up
# separately if you care about it.
#
# LAYOUT RULES (llama.cpp tools/server/README.md, and scan_subdir() in common/preset.cpp):
#   * a single-file GGUF at the TOP LEVEL of a tier dir gets the FILENAME STEM as its id
#   * a multimodal or multi-shard model MUST live in a SUBDIRECTORY, and the projector
#     filename MUST start with "mmproj". The id is then the DIRECTORY NAME
#   * so the subdirectory names below are the exact strings that must appear as section
#     headers in light.ini and as model ids in any client config
#   * every gemma repo names its projector `mmproj-F16.gguf`, which is a second reason
#     the subdirectories are mandatory: they would collide at the top level
#   * draft models live OUTSIDE the tier dirs, in ~/models/drafts, so the directory
#     scanner doesn't try to pair them with a model as a shard/projector
#
# NOTE these take mmproj-F16 where fetch-models-osx.sh takes mmproj-BF16. That is not an
# oversight -- F16 is what is already on disk here, and matching it keeps re-runs free.
set -uo pipefail

# fetch()/fetch_dir_model()/hf_ls()/fetch_report() live in _fetch-lib.sh, shared with
# fetch-models-osx.sh. The shared version adds a size pre-check: `curl -C -` on an
# already-complete file makes the CDN answer 416, which --fail turns into a non-zero
# exit, so the old inline fetch() reported every finished model as FAILED on a re-run.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$SCRIPT_DIR/../shared/_fetch-lib.sh"

# --- heavy tier: one at a time, OPT-IN ------------------------------------------
# 64.2 GB, and NEITHER FILE IS CURRENTLY ON DISK -- heavy.ini's [gpt-oss-120b-MXFP4]
# section and its model-draft both point at nothing right now. The recipe stays here so
# the provenance is recorded, but it is gated: an unguarded `fetch` here means every
# routine re-run of this script silently starts a 64 GB download, which is a nasty
# surprise on a box whose light tier is the thing actually in use.
#
# Same opt-in idiom as fetch-models-osx.sh's LOS_FETCH_MODELS.
#   LOS_FETCH_HEAVY=1 bash fetch-models.sh
if [ "${LOS_FETCH_HEAVY:-0}" = "1" ]; then
  # 63.4 GB. Workhorse: best capability-per-token-rate on this box (~55 t/s).
  fetch ggml-org/gpt-oss-120b-GGUF gpt-oss-120b-MXFP4.gguf "$HOME/models/heavy"
  # 0.8 GB EAGLE3 draft for the above -> spec-type = draft-eagle3 in heavy.ini.
  fetch ggml-org/gpt-oss-120b-GGUF eagle3-gpt-oss-120b-Q8_0.gguf "$HOME/models/drafts"
else
  echo "==> heavy tier skipped (64 GB). Enable with: LOS_FETCH_HEAVY=1"
fi

# --- light tier, subdirectory models (id = directory name) ---------------------
# 16.5 + 0.93 GB. THE DEFAULT MODEL: opencode's `model`/`small_model` and four of its
# agents, plus pi's defaultModel, all resolve to `qwen3.8`. 27.3B, qwen35 arch, vision
# via a qwen3vl_merger projector.
#
# fetch_dir_model, not fetch: the pair on this box is ollama-derived (plain Q4_K_M named
# qwen3.8-Q4_K_M.gguf, 16810714464 bytes, and an mmproj of 931146016) and predates this
# recipe, which yields unsloth's UD-Q4_K_M and a 927607488-byte projector. Plain fetch()
# would see both size mismatches and replace a working, self-consistent pair. The guard
# skips the whole directory when it already holds a model. A fresh machine gets the
# unsloth pair; the id is `qwen3.8` either way, because it is the directory name.
fetch_dir_model unsloth/Qwen3.8-27B-GGUF "$HOME/models/light/qwen3.8" \
  Qwen3.8-27B-UD-Q4_K_M.gguf \
  mmproj-F16.gguf

# 2.89 + 0.92 GB. Vision. The cheapest thing here: classification, OCR, fan-out.
# ALSO the cheap tier's model -- ~/models/cheap/gemma-4-E2B-it/ symlinks the weights
# below (text only, no projector). See cheap.ini for why that tier exists.
fetch unsloth/gemma-4-E2B-it-GGUF gemma-4-E2B-it-Q4_K_M.gguf "$HOME/models/light/gemma-4-E2B-it-GGUF"
fetch unsloth/gemma-4-E2B-it-GGUF mmproj-F16.gguf            "$HOME/models/light/gemma-4-E2B-it-GGUF"

# 4.64 + 0.92 GB. Vision. 8B total params; there is no separate E8B release.
fetch unsloth/gemma-4-E4B-it-GGUF gemma-4-E4B-it-Q4_K_M.gguf "$HOME/models/light/gemma-4-E4B-it-GGUF"
fetch unsloth/gemma-4-E4B-it-GGUF mmproj-F16.gguf            "$HOME/models/light/gemma-4-E4B-it-GGUF"

# 15.78 + 1.11 GB. Vision, 26B total / 4B active.
fetch unsloth/gemma-4-26B-A4B-it-GGUF gemma-4-26B-A4B-it-UD-Q4_K_M.gguf "$HOME/models/light/gemma-4-26B-A4B-it-GGUF"
fetch unsloth/gemma-4-26B-A4B-it-GGUF mmproj-F16.gguf                   "$HOME/models/light/gemma-4-26B-A4B-it-GGUF"

# --- heavy tier ----------------------------------------------------------------
# 87.3 GiB. Qwen3.8-Flash-Next: 125B + 51B n-gram embedding, 6B active. Three shards
# MUST share one subdirectory -- the scanner reads a dir as one multi-shard model and
# the dir name is the id. UD-IQ4_XS over UD-Q4_K_XL (103.7 GiB): the bigger quant does
# not share the tier. The GGUF declares the qwen4exp arch, upstream since 2026-09-05
# (#27742 + fixes) -- llamacpp/archlinux/update.sh keeps the build current, and an
# out-of-date build refuses this model with "unknown model architecture: 'qwen4exp'".
#
# Plain fetch per shard, NOT fetch_dir_model: the guard would see an already-downloaded
# shard and skip the rest, breaking resume. (It excludes *-of-* for exactly this reason,
# but per-shard fetch is clearer here.) Shard 1 is only 10.9 MB -- that is correct, it
# is a metadata-only index shard; shards 2 and 3 carry all 1224 tensors.
fetch unsloth/Qwen3.8-Flash-Next-GGUF UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf "$HOME/models/heavy/Qwen3.8-Flash-Next"
fetch unsloth/Qwen3.8-Flash-Next-GGUF UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00002-of-00003.gguf "$HOME/models/heavy/Qwen3.8-Flash-Next"
fetch unsloth/Qwen3.8-Flash-Next-GGUF UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00003-of-00003.gguf "$HOME/models/heavy/Qwen3.8-Flash-Next"

# --- light tier, single-file models (id = filename stem) -----------------------
# 16.32 GiB. Fan-out: cheap parallel subagents and quick tool calls, and what
# opencode's generate-code subagent targets.
fetch unsloth/GLM-4.7-Flash-GGUF GLM-4.7-Flash-UD-Q4_K_XL.gguf "$HOME/models/light"

# 2.00 GiB. Upstream also ships an mmproj for this one, which we deliberately do NOT
# take: a projector would force it into a subdirectory per the layout rules above and
# change its id from the filename stem to a directory name. Text-only here.
fetch unsloth/Ministral-3-3B-Instruct-2512-GGUF Ministral-3-3B-Instruct-2512-Q4_K_M.gguf "$HOME/models/light"

# 2.33 GiB. Small fast generalist.
fetch unsloth/Qwen3-4B-GGUF Qwen3-4B-Q4_K_M.gguf "$HOME/models/light"

# 0.46 GiB. Official Qwen repo rather than unsloth -- hence the lowercase filename,
# which is also the model id. Tiny; useful as a draft/spec model or a smoke test.
fetch Qwen/Qwen2.5-Coder-0.5B-Instruct-GGUF qwen2.5-coder-0.5b-instruct-q4_k_m.gguf "$HOME/models/light"

# --- removed ------------------------------------------------------------------
# Qwen3-Coder-Next-UD-IQ4_XS (38.4 GB) was dropped by `c901081 clean unusable models`,
# which deleted the file and its light.ini section but left opencode's generate-code
# subagent pointing at it. The router then held a child with `--alias
# Qwen3-Coder-Next-UD-IQ4_XS` and no `--model`, stuck in `loading` forever -- and since
# pick_victim() skips anything not ready, that child could never be evicted and
# permanently occupied one of the five --models-max slots. Re-add a recipe here if you
# ever want it back; do not re-add a client reference without one.

echo
echo "Done. Restart the router to pick up new models:"
echo "  systemctl --user restart llama-router   # or: killport 7070 && los"
echo "Then check nothing has drifted:"
echo "  bash $HOME/dotfiles/bin/llamacpp-audit"

# Non-zero exit if any download failed, so a 404'd filename cannot pass as success.
fetch_report
