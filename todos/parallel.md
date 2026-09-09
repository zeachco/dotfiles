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

- **`los-models` and friends on Linux.** `variants/osx/profile.sh` already has `los-models`,
  `los-loaded`, `los-unload`, `los-check`; Linux has none. They should move into
  `llamacpp/shared/_llama.sh` rather than being duplicated. Tracked as part of the deferred
  "consolidate the three model resolvers" work — `bin/llamacpp-sync` (Python, pi),
  `plugins/llamacpp-model-sync.ts` (opencode), and `_ai_tools.sh:_ai_resolve_model` all implement
  overlapping versions of "ask the router what it serves".
- **Faster models.** Untouched. The cheap tier now has a fast path for shell calls, but nothing new
  was downloaded.
