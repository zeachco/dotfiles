#!/usr/bin/env bash
# Fetch the macOS router's model set. ~29 GB. Resumable and idempotent: re-run to
# continue an interrupted download; a completed file is skipped, not re-reported as
# failed. Safe to run while the router is up -- a directory that appears mid-run is
# picked up on the next router restart (`los-restart`).
#
# Deliberately NOT invoked by setup.sh -- see the note at the end of
# variants/osx/setup.sh. Opt in with LOS_FETCH_MODELS=1.
#
# LAYOUT RULE (llama.cpp v0.3.0 tools/server/README.md):
#   * a single-file GGUF at the TOP LEVEL of --models-dir gets the filename stem as
#     its id;
#   * a multimodal or multi-shard model MUST live in a SUBDIRECTORY, and its
#     projector filename MUST start with "mmproj". The id is then the DIRECTORY name.
#
# All three models here ship an mmproj, so all three get a subdirectory -- and the
# directory names below are therefore the exact strings that must appear as section
# headers in configs/llama/osx.ini and as model ids in any client config. All three
# repos also happen to name the projector `mmproj-BF16.gguf`, which is a second reason
# the subdirectories are mandatory: they would collide at the top level.
#
# MTP draft heads go in ~/models-drafts, a SIBLING of ~/models rather than a
# subdirectory of it: anything under --models-dir is scanned, and three unrelated
# ggufs in one directory would be read as one multi-shard model.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$SCRIPT_DIR/_fetch-lib.sh"

MODELS="${LOS_MODELS_DIR:-$HOME/models}"
DRAFTS="${LOS_DRAFTS_DIR:-$HOME/models-drafts}"

# --- id: gemma-4-E2B-it ---- 3.11 + 0.99 GB. Vision. Cheapest: fan-out, OCR. ------
fetch unsloth/gemma-4-E2B-it-GGUF gemma-4-E2B-it-Q4_K_M.gguf "$MODELS/gemma-4-E2B-it"
fetch unsloth/gemma-4-E2B-it-GGUF mmproj-BF16.gguf           "$MODELS/gemma-4-E2B-it"

# --- id: gemma-4-E4B-it ---- 4.98 + 0.99 GB. Vision. Interactive default. ---------
fetch unsloth/gemma-4-E4B-it-GGUF gemma-4-E4B-it-Q4_K_M.gguf "$MODELS/gemma-4-E4B-it"
fetch unsloth/gemma-4-E4B-it-GGUF mmproj-BF16.gguf           "$MODELS/gemma-4-E4B-it"

# --- id: Qwen3.8-27B ------- 16.46 + 0.93 GB. The "think hard" model. -------------
# NOTE the id differs from the Ryzen box's `qwen3.8` (same model, different directory
# name). Client configs that target both boxes need both strings.
fetch unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-Q4_K_M.gguf "$MODELS/Qwen3.8-27B"
fetch unsloth/Qwen3.8-27B-GGUF mmproj-BF16.gguf           "$MODELS/Qwen3.8-27B"

# --- MTP draft heads ------- 1.57 GB total. Optional speculative decode. ----------
# Cheap enough to always have on disk; wiring them up is a commented-out block at the
# bottom of configs/llama/osx.ini, to be enabled one model at a time after reading the
# accept rate off /metrics.
fetch unsloth/gemma-4-E2B-it-GGUF MTP/mtp-gemma-4-E2B-it-Q8_0.gguf "$DRAFTS"
fetch unsloth/gemma-4-E4B-it-GGUF MTP/mtp-gemma-4-E4B-it-Q8_0.gguf "$DRAFTS"
fetch unsloth/Qwen3.8-27B-GGUF    MTP/mtp-Qwen3.8-27B-Q4_0.gguf    "$DRAFTS"

echo
echo "Layout on disk:"
find "$MODELS" "$DRAFTS" -name '*.gguf' -print 2>/dev/null | sed "s#^$HOME/#  ~/#" | sort

echo
echo "Restart the router, then confirm the ids the router actually assigned:"
echo "  los-restart && los-models"
echo "They must be exactly: gemma-4-E2B-it, gemma-4-E4B-it, Qwen3.8-27B"
echo "Cross-check them against configs/llama/osx.ini with: los-check"

fetch_report
