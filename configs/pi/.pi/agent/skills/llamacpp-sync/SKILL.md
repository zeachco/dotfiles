---
name: llamacpp-sync
description: >
  Sync pi's model definitions with the live llama.cpp routers.
  Use when the llama-server model list changed (new GGUFs placed, models
  removed, router restarted), when asked to reload/update/sync pi models
  from llama.cpp, or when a model served by llama-server is missing from
  /model. Runs the llamacpp-sync script, which rebuilds the llamacpp*
  providers in ~/.pi/agent/models.json from each server's GET /v1/models.
---

# llama.cpp → pi models.json sync

`llamacpp-sync` refreshes pi's `llamacpp*` providers from the live llama.cpp
routers, so `/model` matches what `llama-server` actually serves right now.
Two providers today -- `llamacpp` (light tier, :7070) and `llamacpp-heavy` (:7072,
loads nothing until asked, so it syncs as empty unless a model is loaded). The
remote `llamacpp-olim3` provider was removed; the script still handles several
providers, it just finds one.

## Run

Runs automatically at the end of `dotfiles_update` / `setup.sh` on the Strix Halo box
(llamacpp/archlinux/setup.sh, after the router units are installed). Run it by hand after
adding or removing models, or after loading a model on the heavy tier for the first time.

```sh
~/dotfiles/bin/llamacpp-sync              # sync all llamacpp* providers
~/dotfiles/bin/llamacpp-sync --dry-run    # preview, write nothing
~/dotfiles/bin/llamacpp-sync --provider llamacpp
```

pi reloads `models.json` every time `/model` is opened — no restart needed
after a sync.

## What it refreshes vs. preserves

- **Refreshed:** model membership (models the router no longer serves are
  dropped), `contextWindow` (from the router's launch args, i.e. the current
  `--ctx-size`), `input` modalities (text / text+image).
- **Preserved** for surviving models: `name`, `reasoning`, `thinkingLevelMap`,
  `maxTokens`, `compat`, `cost`, `samplingParams`.
- **New models** get defaults: `reasoning` guessed from the name (qwen3,
  deepseek, glm-4, gpt-oss, ministral, mistral → on), `maxTokens` 16384,
  zero cost. Review and tune those in `models.json` after first sync
  (e.g. `thinkingLevelMap` for qwen3.8-style models).

## Safety rails

- Only providers whose name starts with `llamacpp` are touched; everything
  else in `models.json` is left as-is.
- Unreachable server, empty model list, or a non-llama.cpp response → that
  provider is skipped with a warning, existing defs kept.
- Writes through the real path of `~/.pi/agent/models.json` (a symlink into
  `~/dotfiles/configs/pi/`), so the link is never clobbered; the file is
  git-tracked in `~/dotfiles`.

## Related

- Router state per model (loaded/unloaded, launch args) can be inspected
  with `curl -s http://localhost:7070/v1/models | jq .data`.
- Per-server model pools live in `~/dotfiles/llamacpp/<os>/<tier>.ini`.
- The cheap tier on :7071 (`llama-router-cheap.service`) is deliberately NOT a
  pi provider: it exists for high-frequency shell calls, and adding it back as
  an agent-selectable model would reintroduce the LRU eviction problem it was
  split out to solve. See ryzen-llm-setup.md "The cheap tier".
