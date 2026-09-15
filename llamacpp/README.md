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
| `archlinux/`      | `setup.sh` (installs the three router units), `*.service` templates, `light/cheap/heavy.ini` presets, `fetch-models.sh`, `install.sh`, `update.sh` (checkout + Vulkan build sync, gated to the Strix Halo box) |

Everything is invoked with literal `bash` (not `$SHELL`) because the setup scripts are run
through the user's shell, which would ignore the shebangs.

## Tiers and ports (Arch box)

| Port   | Tier  | Unit                      | Bind        | Models          | Notes                                            |
| ------ | ----- | ------------------------- | ----------- | --------------- | ------------------------------------------------ |
| `:7070` | light | `llama-router.service`    | `0.0.0.0` (LAN) | `~/models/light` | `--models-max 5`, several models coexist         |
| `:7071` | cheap | `llama-router-cheap.service` | `127.0.0.1` | `~/models/cheap` | Isolation tier for high-frequency shell traffic (summarize/tab-autoname), one model, loopback only |
| `:7072` | heavy | `llama-router-heavy.service` | `0.0.0.0` (LAN) | `~/models/heavy` | One model at a time, `--no-models-autoload`      |

The routers are independent processes that **share no memory budget** — a heavy load while the
light tier is busy is a global OOM. The full argument, the 2026-09-09 OOM incident, and the
rules for running heavy sessions live in
[docs/ryzen-llm-setup.md](../docs/ryzen-llm-setup.md) ("The heavy tier", "The cheap tier").

The Mac runs a single router (launchd agent, `osx.ini`) — no tiering.

## How a request flows

`llama-server` runs in **router mode** (no `-m`): it loads nothing until a request names a
model, spawns a **child process per model** (a crash/OOM kills that child, not the endpoint),
and autoloads on first request. Model ids come from the directory/preset entry name, not the
filename — check `GET /v1/models` rather than guessing.

## Presets (`.ini`)

Keys are `llama-server` CLI args without leading dashes. Precedence: router CLI args > model
section > `[*]` global. **Section names must equal the ids the router assigns** — a section that
matches nothing is ignored *without warning* and the model silently falls back to `[*]`.

Three preset-only keys are not CLI args: `load-on-startup`, `stop-timeout`, `dedup-cache-models`.

Per-slot context is `c / np` unless `kv-unified = true` — raising `np` without `kv-unified`
silently quarters what a slot can actually hold, while clients keep advertising the full window
and fail mid-conversation. `bin/llamacpp-audit` enforces this invariant.

## Model lifecycle

```
fetch          llamacpp/<os>/fetch-models*.sh        resumable HF downloads into ~/models/<tier>
verify         llamacpp/shared/verify-models.sh      SHA-256 vs the HF sidecar recorded at fetch
serve          router autoloads from --models-dir    (LLAMA_CACHE per tier keeps tiers isolated)
sync clients   bin/llamacpp-sync  (los → sync-models) rebuilds pi/opencode model defs from /v1/models
audit          bin/llamacpp-audit                    ~/models vs INI presets vs client configs must agree
```

**Every GGUF under `~/models` must have a line in the fetch script** — the audit exists because
that invariant was broken silently before (the default model was a hardlink out of a retired
daemon's blob store).

## Keeping the build current

`update.sh` (per-OS) runs from the variant setup on every `dotfiles_update`: fast-forwards
`~/dev/llama.cpp` and rebuilds when the build is stale, tracked by a **stamp file written only
after a successful build** (never mtime comparison). It never restarts the routers and never
rewrites history; on the Arch box it is additionally gated to Strix Halo hardware. Knobs:
`LLAMACPP_SKIP_UPDATE`, `LLAMACPP_BUILD_FORCE`, `LLAMACPP_REF`, `LLAMACPP_BUILD_JOBS`.
Why the stamp file exists: a half-finished rebuild once served a build six days older than the
checkout, and only new-architecture models failed.

## Deep documentation

- [docs/ryzen-llm-setup.md](../docs/ryzen-llm-setup.md) — the Strix Halo runbook: GTT unlock,
  backend choice (Vulkan vs ROCm), speculative decoding, per-model measurements, incidents.
- File headers are the local manual: `cheap.ini` explains the cheap tier, `_los_menu.sh`
  explains the menu's safety properties, `install.sh` (per-OS) explains the service contract.
