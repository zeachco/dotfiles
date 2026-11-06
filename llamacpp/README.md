# llamacpp/

Local model serving. Only two machines in this repo run local models — an Apple Silicon Mac
(Metal, unified memory) and the Strix Halo desktop (Vulkan, 128 GiB unified memory) — and
`shared/_hw-gate.sh` is the single place that decision is made, so no other host that runs
`dotfiles_update` installs llama.cpp, installs a router service, or rebuilds anything.

## Layout

| Path              | What it is                                                                                                     |
| ----------------- | -------------------------------------------------------------------------------------------------------------- |
| `shared/`         | Cross-OS, sourced by the shell profile: `_llama.sh` (foreground launchers + verbs), `_los_menu.sh` (the `los` fzf menu), `_fetch-lib.sh` (HuggingFace download helper), `verify-models.sh` (GGUF integrity vs HF SHA-256), `clone.sh` (clones `~/dev/llama.cpp`, starts initial downloads), `_hw-gate.sh` |
| `osx/`            | `setup.sh` (brew install + launchd user agent + wired-memory cap daemon), `osx.ini` presets, `install*.sh` + plist templates, `fetch-models-osx.sh` (opt-in via `LOS_FETCH_MODELS=1`), `update.sh` (build sync) |
| `archlinux/`      | `setup.sh` (installs the router unit), `llama-router.service` template, `models.ini` presets, `fetch-models.sh`, `install.sh` (also retires the pre-2026-11-06 tier units and migrates `~/models/{light,heavy,cheap}` into `~/models/llama`), `update.sh` (checkout + Vulkan build sync, gated to the Strix Halo box) |

Everything is invoked with literal `bash` (not `$SHELL`) because the setup scripts are run
through the user's shell, which would ignore the shebangs.

## The router (Arch box)

| Port   | Unit                   | Bind            | Models           | Notes |
| ------ | ---------------------- | --------------- | ---------------- | ----- |
| `:7070` | `llama-router.service` | `0.0.0.0` (LAN) | `~/models/llama` | `--no-models-autoload`, `--models-max 8`: nothing loads until `los` / `los-load` / pi's model picker asks, nothing is evicted behind your back; memory is the only budget |

One router since 2026-11-06. Before that there were three (light `:7070` with autoload,
cheap `:7071` for the shell helpers, heavy `:7072` one-at-a-time) whose whole reason was
to keep the autoloading tier's LRU eviction away from the daily model and the shell
helpers; with autoload off everywhere the split had nothing left to do, and routers that
shared no memory budget were the shape of two global OOMs. The history and the incidents
live in [docs/ryzen-llm-setup.md](../docs/ryzen-llm-setup.md).

Everything under `~/models/llama` is advertised, so that directory holds ONLY served
models: drafts live in `~/models/drafts`, the Laya encoder in `~/models/laya`, parked
weights in `~/models/retired`.

The Mac runs a single router too (launchd agent, `osx.ini`), with autoload.

## How a request flows

`llama-server` runs in **router mode** (no `-m`): it spawns a **child process per model** (a
crash/OOM kills that child, not the endpoint) and proxies by the request's `model` field. On
the Arch box a model has to be loaded first (`los`, `los-load`, `POST /models/load`, or picking
it in pi); a request for an unloaded model is refused with 400. The Mac autoloads on first
request. Model ids come from the directory/preset entry name, not the filename — check
`GET /v1/models` rather than guessing.

## Presets (`.ini`)

Keys are `llama-server` CLI args without leading dashes. Precedence: router CLI args > model
section > `[*]` global. **Section names must equal the ids the router assigns** — a section that
matches nothing is ignored *without warning* and the model silently falls back to `[*]`.

Three preset-only keys are not CLI args: `load-on-startup`, `stop-timeout`, `dedup-cache-models`.

Two ordinary CLI args do most of the work of sharing one GPU between agents, and both are set
per model in `models.ini` (2026-10-11): `sleep-idle-seconds` makes an idle child release its
weights and KV and reload on the next request (so idle fan-out models stop pinning GTT; the
router reports such a model as `sleeping`, which the `los` menu and `framework-rgb` must never
probe with `/slots`, because that wakes it), and `kv-unified-per-slot` caps what one chat can
take out of a shared KV pool (so one long conversation cannot starve the other slots).
`models.ini`'s comments carry the measured load and re-ingest costs behind the values.

Per-slot context is `c / np` unless `kv-unified = true` — raising `np` without `kv-unified`
silently quarters what a slot can actually hold, while clients keep advertising the full window
and fail mid-conversation. `bin/llamacpp-audit` enforces this invariant.

## Model lifecycle

```
fetch          llamacpp/<os>/fetch-models*.sh        resumable HF downloads into ~/models/llama (plus non-router models such as `~/models/laya`)
fetch missing  bin/llamacpp-fetch-missing            same recipe, plan pass first (LOS_FETCH_PLAN): lists what is missing, asks [y/N]; the `models` Herdr job of dotfiles_update, i.e. the LAST step of setup. On a box with no model yet it is an fzf multi-select over every model the recipe knows (big ones included) and fetches only what was picked (LOS_FETCH_SELECT)
verify         llamacpp/shared/verify-models.sh      SHA-256 vs the HF sidecar recorded at fetch
serve          router serves --models-dir            loads on request only (Arch); LLAMA_CACHE pinned so the cache cannot add models
sync clients   bin/llamacpp-sync  (los → sync-models) rebuilds pi/opencode model defs from /v1/models
pi discovery   configs/pi/.pi/agent/extensions/llamacpp-discover.ts  pi re-reads the router's /v1/models itself at startup (models.json = offline fallback) and loads a picked model when it fits
restart all    los-restart-all    (los → restart) restarts the router daemon, reachable or not
audit          bin/llamacpp-audit                    ~/models vs INI presets vs client configs must agree
```

Marking several models in `los` loads them **4 at a time** (`LOS_LOAD_PARALLEL`; `=1` restores
the serial batch). Each model is its own child process, so the router parallelizes loads whether
the menu does or not — serializing there only added the sum of the load times. What is kept: a
failing round still stops the batch (memory), and `los` still runs every unload as a group
before the first load. What is not metered: up to 4 loads allocate at once, so the preview's
fits / does-NOT-fit line is the only brake before you mark a batch.

Laya is kept outside the llama.cpp router tiers because it is a ggmlc decision/encoder model,
not a text-generation model. On Arch, `fetch-models.sh` downloads and verifies the English Q8
checkpoint to `~/models/laya`; run it with `bash ~/dotfiles/llamacpp/archlinux/fetch-models.sh`.
Install the matching runner from the ggmlc release with the Linux Vulkan artifact. Use
`/usr/bin/install`, not bare `install`: the dotfiles define `install()` as a package helper.

**Decision models are a different case.** `Bespoke-Nimble-9B-v3`
is a real llama.cpp model whose GGUF carries `<arch>.decision.type = nimble`. The router reports
it in `/v1/models` with `architecture.output_modalities = ["decisions"]` without loading it, so
pi's built-in llama.cpp provider lists it **only** as a classifier — llama.cpp's `/v1/systemone`
endpoint, the `typesafe-system-one` API, and never in `/model`. `bin/llamacpp-sync` drops such
models from the chat defs it writes (pi re-discovers them from the router; opencode has no
classifier concept). To use a local classifier in pi you must be logged into the built-in
`llama.cpp` provider (`/login llama.cpp`, or `LLAMA_BASE_URL=http://127.0.0.1:7070`) — the
custom `llamacpp` provider in `models.json` only serves chat. A classify call does not load
it (no autoload): load it beside `qwen3.8` with `los` when a session wants it.

**Every GGUF under `~/models` must have a line in the fetch script** — the audit exists because
that invariant was broken silently before (the default model was a hardlink out of a retired
daemon's blob store).

## Keeping the build current

`update.sh` (per-OS) runs from the variant setup on every `dotfiles_update`: fast-forwards
`~/dev/llama.cpp` and rebuilds when the build is stale, tracked by a **stamp file written only
after a successful build** (never mtime comparison). It never restarts the routers on its own:
after a successful build it asks `[y/N]` when a terminal is attached (showing how many slots are
mid-generation first, and giving up after two minutes), and only prints the reminder otherwise. It
never rewrites history; on the Arch box it is additionally gated to Strix Halo hardware. Knobs:
`LLAMACPP_SKIP_UPDATE`, `LLAMACPP_BUILD_FORCE`, `LLAMACPP_REF`, `LLAMACPP_BUILD_JOBS`,
`LLAMACPP_RESTART` (`1` restart without asking, `0` never ask).
Why the stamp file exists: a half-finished rebuild once served a build six days older than the
checkout, and only new-architecture models failed.

## Deep documentation

- [docs/ryzen-llm-setup.md](../docs/ryzen-llm-setup.md) — the Strix Halo runbook: GTT unlock,
  backend choice (Vulkan vs ROCm), speculative decoding, per-model measurements, incidents.
- File headers are the local manual: `models.ini` explains every model's budget, `_los_menu.sh`
  explains the menu's safety properties, `install.sh` (per-OS) explains the service contract.
