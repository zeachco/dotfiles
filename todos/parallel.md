# Parallelism / model visibility

Original ask: "configure llamacpp to run with more parallels models than 4 (maybe 8); also make
sure there are faster models downloaded and create an alias like `los` but only shows the
available models for llamacpp".

## Resolved

**"More parallel" was two different knobs, and only one of them was the right one to raise.**

- `np` / `--parallel` = server *slots per model*. Slots are sticky per conversation, so `np` below
  the concurrent client count is a permanent prefix-cache thrash loop (measured: one slot
  generating at 0.06 t/s while another re-ingested 45k tokens at ~116 t/s). This is the one to
  raise, and it is cheap. Raised from 2 → 4 on `[GLM-4.7-Flash-UD-Q4_K_XL]` and
  `[Qwen3.8-Flash-Next]`; `[qwen3.8]` is at 6, `[*]` at 4.
- `--models-max` = *resident model count*. This is what consumes memory, and it evicts on model
  count, never on bytes. Left at 5, now kept in sync between `llama-router.service` and `los()`
  (they had drifted to 5 vs 4). Raising it to 8 would have made things worse, not better — the box
  was already at 79% of the 62.5 GiB GTT cap with 13 GiB in swap.

The real cause of "the light tier is taxing the machine" was two things, neither of them
parallelism:

1. The Phase 0 GTT unlock was staged but never booted, so the GPU could address only half of RAM.
2. Router eviction is pure LRU on `last_used` with no way to pin a model, and every POST refreshes
   the target's timestamp — so `summarize`/`tab_autoname` firing on every tab rename kept evicting
   qwen3.8. Fixed by moving that traffic to `llama-router-cheap.service` on :8081. See
   `ryzen-llm-setup.md` → "The cheap tier".

## Still open

- **`los-models` and friends on Linux.** *Largely addressed 2026-09-10* by the `los` fzf menu
  (`llamacpp/shared/_los_menu.sh`): listing, load, unload, per-model config and live slot state
  are all in one place, across all three tiers rather than the one router the macOS helpers
  assume. Still open: `los-check` has no equivalent — the menu shows each model's `.ini` section
  but does not diff section names against the router's ids, and a section matching no id is
  ignored silently. The macOS helpers in `variants/osx/profile.sh` remain a separate
  implementation.
- **Consolidate the three model resolvers.** *Half done 2026-09-10* — `bin/llamacpp-sync` now
  writes both clients (pi's `models.json` and opencode's `opencode.json`), and the `los` menu's
  `sync-models` action is the one entry point. That makes
  `configs/opencode/.config/opencode/plugins/llamacpp-model-sync.ts` redundant, and it is worth
  deleting rather than keeping: it throws on the `//` comment in `opencode.json` and silently
  no-ops today, and if that comment ever went away it would start round-tripping the file through
  `JSON.stringify` — eating every comment the next one adds. Still open: `_ai_tools.sh:_ai_resolve_model`
  is a third reader of `/v1/models`, and the menu a fourth (read-only).
- **Faster models.** Untouched. The cheap tier now has a fast path for shell calls, but nothing new
  was downloaded.
