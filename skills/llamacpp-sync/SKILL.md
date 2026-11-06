---
name: llamacpp-sync
description: >
  Sync pi's and opencode's model definitions with the live llama.cpp router and
  OpenRouter. Use when a local model list changed, when asked to reload/update/sync
  models, or when a model is missing from /model. Runs llamacpp-sync, which rebuilds
  the llamacpp* and openrouter providers in both client configs from GET /v1/models.
---

# llama.cpp → client model sync

`llamacpp-sync` refreshes the `llamacpp*` and `openrouter` providers of both local
clients from their live OpenAI-compatible endpoints, so each client has the same
current model catalog:

| client   | file                              | shape                              |
| -------- | --------------------------------- | ---------------------------------- |
| pi       | `~/.pi/agent/models.json`         | `providers.<name>.models` array     |
| opencode | `~/.config/opencode/opencode.json`| `provider.<name>.models` object     |

The local provider is `llamacpp` (the one router on :7070, `--no-models-autoload`; it
still lists models when nothing is loaded; big and small models alike). The
`openrouter` provider is filtered to text-output chat models and uses the public
OpenRouter catalog; requests use `OPENROUTER_API_KEY` or the client's stored login.

## Run

Runs automatically at the end of `dotfiles_update` / `setup.sh` on the Strix Halo box
(llamacpp/archlinux/setup.sh, after the router unit is installed), and is the
`sync-models` action in the `los` menu. Run it by hand after adding or removing models.

pi's `llamacpp` provider no longer waits for a sync: the
`llamacpp-discover.ts` extension (configs/pi/.pi/agent/extensions) registers the
models.json list instantly, then re-reads `/v1/models` in the background after every
session start (`/llamacpp-refresh` does it on demand) with the same filtering rules, and
empties a provider whose router port refuses connections (router not installed on this box);
only transient failures keep the models.json list. A sync is still what updates opencode and
the offline fallback itself.

```sh
~/dotfiles/bin/llamacpp-sync                  # both clients, local + OpenRouter
~/dotfiles/bin/llamacpp-sync --dry-run        # preview, write nothing
~/dotfiles/bin/llamacpp-sync --client pi      # one client only
~/dotfiles/bin/llamacpp-sync --provider llamacpp
~/dotfiles/bin/llamacpp-sync --provider openrouter
```

pi reloads `models.json` every time `/model` is opened — no restart needed after a
sync. opencode reads its config at startup, so restart it.

## What it refreshes vs. preserves

- **Refreshed:** model membership (models the router no longer serves are
  dropped), the per-slot context (`contextWindow` for pi, `limit.context` for
  opencode — `--ctx-size` divided by `--parallel` unless `--kv-unified`), and
  image input (`input` / `attachment`).
- **Hidden from pi:** the router's `gemma-4-*` models never enter pi's
  `llamacpp` provider (`PI_HIDDEN` in the script; the sync prints which ones it
  kept out). pi routes nothing to them and `enabledModels` hides them from
  `/model`; opencode still lists them.
- **Preserved** for surviving models: pi's `name`, `reasoning`,
  `thinkingLevelMap`, `maxTokens`, `compat`, `cost`, `samplingParams`; every key
  an opencode entry already carries, including ones the script never writes.
- **New local models** get defaults: `reasoning` guessed from the name, 16384
  output tokens, zero cost, and `tool_call: true` for opencode.
- **New OpenRouter models** get context/output limits, image input, reasoning,
  tool support, and pricing from the catalog. The catalog is filtered to models
  that produce text, so image-only models are not added to either chat picker.

## Safety rails

- Only providers whose name starts with `llamacpp` or equals `openrouter` are
  touched; everything else in either file is left as-is.
- An unreachable endpoint, empty model list, or invalid response → that provider
  is skipped with a warning and existing definitions are kept.
- Writes through the real path of each file (both are symlinks into
  `~/dotfiles/configs/`), so the links are never clobbered; both files are
  git-tracked in `~/dotfiles`, so a sync leaves a diff to review.
- `opencode.json` is JSONC and hand-maintained (MCP servers, agents,
  commented-out keys): only the `models` object of each syncable provider is
  spliced in place, and the rest of the file — comments included — comes out
  byte-identical.

## Related

- Router state per model (loaded/unloaded, launch args) can be inspected
  with `curl -s http://localhost:7070/v1/models | jq .data`, or by hovering a
  model in the `los` menu.
- Per-model presets live in `~/dotfiles/llamacpp/archlinux/models.ini` (Mac: `osx/osx.ini`).
- `bin/llamacpp-audit` cross-checks `~/models`, the INI presets and both client
  configs; run it after a sync that added a model.
