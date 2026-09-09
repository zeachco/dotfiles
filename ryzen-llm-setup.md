# Local LLM setup — Ryzen AI MAX+ 395 (Strix Halo, 128 GiB)

Runbook for AMD Ryzen AI MAX+ 395 / Radeon 8060S (gfx1151), 128 GiB unified memory,
Omarchy 4.0, Limine + measured UKI.

Priorities this setup optimizes for, in order: **flexibility** (switch models freely, experiment with
small ones, still able to run the big ones), **stability** (long autonomous loops must not time out
or die), then speed.

## Where things stand

- `~/dev/llama.cpp` on **`master`**, built in `build/` with **`GGML_VULKAN=ON`,
  `GGML_HIP=OFF`** — Vulkan only. `llamacpp/archlinux/update.sh` fast-forwards and
  rebuilds it on every `dotfiles_update`; see "Keeping the build current" below.
- `llamacpp/shared/_llama.sh` defines the three tier launchers over one `_los_router` helper:
  `los` (light, :7070), `los-cheap` (:7071), `los-heavy` (one model at a time). The original
  fzf-over-`ollama list` launcher was deleted along with ollama itself — see "Retiring ollama".
- `~/models/DeepSeek-V4-Flash-chat-v2/…-chat-v2-imatrix-fixed.gguf` — **90.9 GiB** hand-tuned mixed
  quant (layers 37–42 experts Q4_K, other expert layers IQ2_XXS gate/up, Q2_K down,
  attn-proj/shared-experts/output Q8). `general.architecture = deepseek4`.
- ~~`ollama` 0.32.14 (`/usr/local/bin`, hand-installed), 91 GB of models~~ — **retired**. It was
  running the ROCm backend and refusing Vulkan (`dropping integrated GPU; to enable, set
  OLLAMA_IGPU_ENABLE=1`), and its ~95 GB of weights duplicated `~/models`. Nothing served
  through it. See "Retiring ollama" below.
- `~/.config/opencode/opencode.json` (symlinked into `configs/opencode/`) points a single
  `llamacpp` provider at `http://oli-llms.local:7070/v1` with per-model `limit.context` matching
  `light.ini`. The `llamacpp-olim3` provider for the M4 was removed — that box is no longer a
  dependency of this one. `headerTimeout` is left at its 300s default rather than disabled, so a
  request queued behind `--models-max` surfaces instead of hanging forever.

## Keeping the build current

`llamacpp/archlinux/update.sh` runs from the Arch profile setup, so `dotfiles_update`
fast-forwards `~/dev/llama.cpp` and rebuilds when the build has fallen behind.

Why it exists — **2026-09-08, Qwen3.8-Flash-Next would not load:**

```
E llama_model_load: error loading model: unknown model architecture: 'qwen4exp'
```

The checkout had qwen4exp support. The *build* did not. `build/` held a half-finished
rebuild: `libggml-base`/`libggml-cpu` relinked to 0.22.0 on Aug 27, while `libllama.so`
and `llama-server` were still Aug 19 artifacts — six days older than the commit that
added the arch. Nothing surfaced it. `git log` looked current, the router started
normally, and every already-supported model kept working; only a model needing a *new*
architecture failed, and it failed as if the model were at fault.

Root cause, found 2026-09-08 after two more silent failures: `pacman -Rns vulkan-headers`
had been run by hand on 2026-08-25. Every rebuild since died on
`fatal error: vulkan/vulkan_core.h: No such file or directory`, invisible inside `-j16`
output. `variants/archlinux/setup.sh` now installs `vulkan-headers` and `shaderc`, and
`update.sh` refuses to build without them and tees the build to
`~/.cache/dotfiles-llamacpp-build.log`, printing the first errors on failure.

Design consequences, each one paid for by that:

- **Staleness is a stamp file** (`build/.dotfiles-build-commit`), written only after a
  build exits 0 — never an mtime comparison. An interrupted build leaves the stamp
  stale and the next run retries, which is exactly what mtime got wrong.
- **It never restarts the routers.** A restart drops in-flight generation, and a long
  prompt ingest is minutes of work. It reports which units still run the old binary
  instead. Worth restarting at the next break rather than sitting on it: the router
  forks a child per model, so after a relink a newly autoloaded child runs new code
  under a parent still mapped to the old.
- **It never rewrites history.** Dirty tree, diverged branch, or a checkout parked on
  some other ref: it reports and declines. A deliberate PR-branch checkout still gets
  its *binary* rebuilt, so a pinned branch is never served by a stale build.
- **It is gated to this box** — omarchy plus `ryzen ai max` in `/proc/cpuinfo`. Nothing
  else running these dotfiles should spend 32 cores on a Vulkan rebuild at login.
- **ccache is wired in** (`CMAKE_{C,CXX}_COMPILER_LAUNCHER`). It was installed but
  unused — 0 hits in 54 lookups — which is most of why rebuilding felt expensive
  enough to defer.

Knobs: `LLAMACPP_SKIP_UPDATE=1`, `LLAMACPP_BUILD_FORCE=1`, `LLAMACPP_REF=<branch>`,
`LLAMACPP_BUILD_JOBS=<n>` (default half the cores, same headroom logic as CPUQuota).

**Tracking a not-yet-merged arch.** Qwen3.8-Flash-Next arrived this way — checked out
from unsloth's PR #27742 branch. That is fine, but it is a *temporary* state: the PR
merged 2026-09-05 as `6c84c7d5d`, and master then collected four follow-up fixes
(#27880 graph splits, #27941 seq_cp/mtmd/tests, #28023 indexer heads, #28123 recurrent
state rollback) that the PR branch never had. Get back onto `master` once a PR lands —
`update.sh` will tell you it is skipping the pull for as long as you are parked
somewhere else.

## Routing work between models (pi)

`configs/pi/.pi/agent/` carries the client-side half of this setup, stowed to `~/.pi/agent/`:
agent definitions with a pinned `model:` (`worker`, `scout` on GLM-4.7-Flash; `planner`,
`reviewer` on qwen3.8), `/preset think|build` for switching the main session, `/implement`,
`/build`, `/review` workflows, and a global `AGENTS.md` telling the slow model when to delegate.
Two hot models on purpose — the LRU eviction described below has no pinning.

One llama.cpp-specific detail lives in `models.json`: GLM's `thinkingLevelMap` maps `off` to
`reasoning_effort: "none"`, the only value llama-server treats as "disable reasoning"
(`tools/server/server-common.cpp`, `reasoning_effort == "none"`). Without it a `:off` subagent
still thinks. Measured 2026-09-08: default → 40 tokens of `reasoning_content` and an empty
answer; `"none"` → the answer in 2 tokens.

## Ports

| Port | Tier | Unit | Host | Models |
|---|---|---|---|---|
| `:7070` | light | `llama-router.service` | `0.0.0.0` (LAN) | `~/models/light`, `--models-max 5` |
| `:7071` | cheap | `llama-router-cheap.service` | `127.0.0.1` | `~/models/cheap`, gemma-E2B only |
| `:7072` | heavy | `llama-router-heavy.service` | `0.0.0.0` (LAN) | `~/models/heavy`, `--models-max 1`, `--no-models-autoload` |

Moved off 8080/8081 on 2026-09-08 because 8080 is a common dev-server port. A port change
only takes effect when the unit restarts; `install.sh` deliberately does not do that
(`enable --now` is a no-op for a running unit), so after pulling this: `systemctl --user
restart llama-router.service llama-router-cheap.service` when idle. Clients (`pi` `models.json`,
opencode, `AI_LLAMA_URL`) already point at the new ports.

## The heavy tier

`llama-router-heavy.service` on **:7072** serves `~/models/heavy` one model at a time and loads
nothing until asked (`--no-models-autoload`; load with `/llama` in pi, or
`curl -X POST localhost:7072/models/load -d '{"model":"Qwen3.8-Flash-Next"}'`). It exists for
models that cannot share the GPU with the daily set: Qwen3.8-Flash-Next (~87 GiB) and the
90.9 GiB DeepSeek. On the light tier such a model would be loaded by LRU *eviction* of qwen3.8
and GLM — every other live session then pays a multi-minute reload the moment it comes back.

What a separate router does **not** buy is memory. The routers do not coordinate: with qwen3.8 +
GLM resident on :7070 (~60 GiB) a Flash-Next load on :7072 simply fails on the GPU. So a heavy
session is explicit: `los-drain` (unloads every model on :7070, keeps the router up), then load
the heavy model. The light models reload on demand afterwards. That trade — an explicit step
instead of a surprise eviction — is the whole point of the tier.

pi sees it as a second provider, `llamacpp-heavy`; `llamacpp-sync` refreshes both.

## The four findings that drive this runbook

1. **The GPU can only address 62.5 GiB, so the 90.9 GiB DeepSeek cannot load at all.**
   `mem_info_gtt_total` = 67152236544, and `ttm.pages_limit` = 16394586 pages — both the default
   "half of RAM" cap, not a memory shortage. BIOS UMA is already at the ideal 512 MB
   (`mem_info_vram_total` = 536870912), so it's a one-line kernel-cmdline fix. **Nothing else here
   matters until Phase 0 is done.** This also bites the light tier, not just DeepSeek: with five
   children resident, `mem_info_gtt_used` sits near 50 GiB of the 62.5 GiB cap and the box swaps.
2. **`llama-server` has a built-in router mode, already present in this build**
   (`tools/server/server-models.cpp`). It serves many models from one port, autoloads on demand,
   isolates each model in a child process, and supports resumable SSE streams. This replaces both the
   fzf-relaunch flow and any need for llama-swap — see Phase 1.
3. **`los` couldn't see the DeepSeek model anyway** — the original launcher enumerated
   `ollama list` only, and a 90.9 GiB hand-quant will never be in ollama's registry. Router mode
   (finding 2) removed that constraint, and ollama has since been retired outright.
4. **Mainline llama.cpp already supports the model and ships speculative decoding for it.**
   `LLM_ARCH_DEEPSEEK4` and `llama_model_deepseek4` are in `src/` at b10524, so the "you need the
   nisparks fork" advice is obsolete. And `common/arg.cpp` carries
   `COMMON_SPECULATIVE_TYPE_DRAFT_DSPARK` / `DRAFT_DFLASH` with HF sidecar auto-discovery.
   Speculation is the one lever that moves decode on a bandwidth-bound APU (~120 GB/s LPDDR5X), and
   it's likely what separates the 13 t/s and 32 t/s figures people report for this model on this
   chip.

## Backend choice: not Vulkan-only

The split on gfx1151 is by phase _and_ context depth.

| Backend               | pp512   | tg128  | pp512 @ 130k depth |
| --------------------- | ------- | ------ | ------------------ |
| Vulkan RADV           | 755 t/s | 85 t/s | **17 t/s**         |
| Vulkan AMDVLK         | 742     | 82     | 10.7               |
| ROCm (tuned, rocWMMA) | 659     | 68     | **51 t/s**         |

(Qwen3-30B-A3B UD-Q4_K_XL; see sources.) Short-context interactive chat wants Vulkan; long-context
agent loops want ROCm+rocWMMA. RADV also has a **4 GiB per-allocation cap** that has specifically
broken 90 GB+ models (llama.cpp #13024) — a second reason to keep a HIP build around for the
DeepSeek tier.

---

## Retiring ollama

Nothing served through it once router mode landed: `ollama serve` sat resident doing nothing while
its store held ~95 GB duplicating `~/models`. It also lagged upstream llama.cpp by weeks on new
architectures, which is the opposite of what this box is for.

It was **not** a managed package — `pacman -Qq | grep ollama` was empty, the binary came from
upstream's install script in `/usr/local/bin`, and `ollama.service` was a **system** unit, not a
`--user` one:

```bash
sudo systemctl disable --now ollama.service
sudo rm -f /etc/systemd/system/ollama.service /usr/local/bin/ollama
sudo rm -rf /usr/local/lib/ollama          # bundled libs, incl. its private rocm_v7_2
sudo systemctl daemon-reload
sudo userdel ollama 2>/dev/null            # service user the installer creates
rm -rf ~/.ollama                           # the ~95 GB of weights
```

Repo-side, this removed `llama-ollama-server`/`los-pick`, `_los_free_memory` **and its call site
in `_los_router`** (deleting the function alone would have broken `los` and `los-heavy`),
`codeai`/`speakai`/`pie_score`, the macOS `OLLAMA_CONTEXT_LENGTH` `launchctl setenv` and
`los-free`, and the unused `variants/debian/Modelfile`. Nothing in any `setup.sh` installed
ollama, so there is no risk of `setup.sh` reinstating it — the only `ollama` strings left in
`framework-ryzen/setup.sh` *remove* a legacy `ollama-framework-rgb.service`.

Two false positives to leave alone: `configs/pi/.pi/agent/settings.json` matches a grep for
"ollama" only because of the pi package `npm:@ollama/pi-web-search` (an npm scope, unrelated to
the daemon), and the `com.zeachco.llama-router.plist` hit is an explanatory comment.

---

## Phase 0 — Unlock GTT (reboot; blocks everything)

> **Status: STAGED, PENDING REBOOT.** `/etc/limine-entry-tool.d/amdgpu-gtt.conf` is in place and
> the UKI has been verified to carry `amdgpu.gttsize=131072 ttm.pages_limit=31457280`. The running
> kernel does **not** — `/proc/cmdline` has neither param and `mem_info_gtt_total` is still
> 62.5 GiB. Nothing further is needed but a reboot.

Cmdline is assembled by **limine-entry-tool**, not read from `/etc/kernel/cmdline`.

`/etc/default/limine` sets the base with the `+=` operator:

```
KERNEL_CMDLINE[default]+="cryptdevice=... rw rootfstype=btrfs"
```

and per `limine-entry-tool.conf`, using `+=` there makes the tool **ignore
`/etc/kernel/cmdline` and `/proc/cmdline` outright**. Editing `/etc/kernel/cmdline` on this box
is a silent no-op no matter how many times `limine-update` runs. (Cost weeks here: the args sat
in `/etc/kernel/cmdline` from ~2026-08 until 2026-09-04 while GTT stayed at the 62.5 GiB default.)

Add a drop-in instead, matching the existing `resume.conf` / `rtc-alarm.conf` pattern:

```bash
pkexec tee /etc/limine-entry-tool.d/amdgpu-gtt.conf >/dev/null <<'EOF'
KERNEL_CMDLINE[default]+=" amdgpu.gttsize=131072 ttm.pages_limit=31457280"
EOF
pkexec limine-update
```

Use `pkexec`, not `sudo` -- there is no tty on this box for a `sudo` password prompt, so
`sudo limine-update` fails silently in a non-interactive context. hyprpolkitagent answers pkexec.

**Verify the UKI before rebooting** -- `limine-update` reporting success only means it built an
image, not that it picked up your parameters:

```bash
pkexec objcopy -O binary --only-section=.cmdline \
  /boot/EFI/Linux/omarchy_linux.efi /dev/stdout | tr -d '\0'
```

Then after the reboot, verify both -- the first catches a cmdline that never made it in, the
second catches a param the running kernel rejected:

```bash
grep -o 'ttm.pages_limit=[0-9]*' /proc/cmdline
cat /sys/class/drm/card1/device/mem_info_gtt_total   # expect ~128 GiB, not 67152236544
```

`/sys/module/amdgpu/parameters/` has no `gttsize` entry even when the param took effect -- it is
declared with perm 0, so sysfs never exposes it. Use `modinfo amdgpu | grep gttsize` to confirm the
param still exists on a new kernel; check GTT via `mem_info_gtt_total`, never via sysfs params.

128 GiB GTT cap / 120 GiB TTM page cap. These are _caps_, not reservations — nothing is taken from
the OS.

- Leave BIOS UMA at 512 MB. Raising it _reduces_ usable memory.
- Do **not** add `amd_iommu=off` — it disables the NPU and breaks suspend, for a couple of benchmark
  points.

## Phase 1 — Router mode: one port, many models

Launch `llama-server` **without** `-m` and it starts as a router: it loads no model, never touches
the GPU (`server.cpp:134`), and spawns a **child process per model**, forwarding each request by the
`"model"` field in the JSON body (or `?model=` on GET endpoints). Models autoload on first request.

Why this fits the priorities:

- **Flexibility** — switch models by name, no restart. Per-model flags live in a git-tracked INI.
- **Stability** — one model per child process, so a crash or OOM kills that child, not the router,
  not the other models, not the endpoint.
- **Long sessions** — resumable SSE streams (see Phase 6) keep a generation alive across client
  disconnects.

Management endpoints: `POST /models/load`, `POST /models/unload`, `DELETE /models`, and
`GET /models/sse` for a live status feed.

### Two sharp edges

- **`--models-max` defaults to 4.** The router counts _models_, not _bytes_, and knows nothing about
  the GTT budget. Four loaded models with a 90.9 GiB one among them is an instant OOM. This is why
  there are two launchers below rather than one.
- **Cached models are always enumerated** (`server-models.cpp:506`, unconditional), before
  `--models-dir` and `--models-preset`. Filtering the big model out of a tier therefore means
  controlling `LLAMA_CACHE` as well as the model directory.

### Directory split

Filtering is by directory, which is the only mechanism the router gives us:

```
 ~/models/
 ├─ light/                              # ≤ ~45 GB, several can coexist (the 87 GiB Flash-Next is the exception)
 │   ├─ Qwen3-Coder-Next-UD-Q4_K_XL/
 │   ├─ Qwen3.8-Flash-Next/             # 3 shards, UD-IQ4_XS, ~87 GiB
 │   └─ GLM-4.7-Flash-Q4_K_M.gguf
 └─ heavy/                              # one at a time
     ├─ DeepSeek-V4-Flash-chat-v2/      # move the existing dir here
     └─ gpt-oss-120b-MXFP4.gguf         # ~63 GB — also heavy
```

Multi-shard and multimodal models go in a **subdirectory**; single files sit at top level. The
existing `DeepSeek-V4-Flash-chat-v2/` already has the right shape — just `mv` it under `heavy/`.

### The two launchers

**Implemented** in `llamacpp/shared/_llama.sh`. There are now **three** launchers, not two — the
cheap tier was split out onto :7071 (see "The cheap tier" below). The original fzf-over-`ollama
list` function and the `_los_free_memory` helper that stopped resident ollama runners were both
deleted when ollama was retired.

```bash
LOS_CONF_DIR="${LOS_CONF_DIR:-$HOME/dotfiles/llamacpp/archlinux}"

_los_router() {
  local tier="$1" max="$2"; shift 2
  ensure_llama_cpp || return 1
  LLAMA_CACHE="$HOME/.cache/llama.cpp-$tier" \
    "$LLAMA_CPP_BUILD/bin/llama-server" \
      --models-dir "$HOME/models/$tier" \
      --models-preset "$LOS_CONF_DIR/$tier.ini" \
      --models-max "$max" \
      --host 127.0.0.1 --port "${LOS_PORT:-7070}" \
      -to 3600 \
      "$@"
}

# Small/medium models, up to 5 resident -- matches llama-router.service's --models-max.
# DeepSeek-class is excluded by directory.
los() { _los_router light 5 "$@"; }

# One model at a time, the big ones.
los-heavy() { _los_router heavy 1 "$@"; }

# High-frequency shell traffic only, on its own port. See "The cheap tier".
los-cheap() { LOS_PORT="${LOS_PORT:-7071}" _los_router cheap 1 "$@"; }
```

`los` binds :7070, `los-cheap` :7071 and `los-heavy` :7072 — the same ports as the three
systemd units, so a foreground run of any tier behaves like its service. Run `los-drain` before a
heavy session: the routers do not coordinate memory (see "The heavy tier" below).
Extra args pass straight through, and children inherit the router's argv _and_ environment, so
`GGML_VK_FORCE_MAX_ALLOCATION_SIZE=… los-heavy` works as expected.

Separate `LLAMA_CACHE` per tier is what stops an `-hf` pull in one tier from showing up in the other.

### The cheap tier

`llama-router-cheap.service` on **:7071**, one model, loopback only. It is an *isolation*
boundary, not a performance tier, and the reason is a specific property of the router's
eviction:

- The victim is chosen by **pure LRU on `last_used`** — `pick_victim()` in
  `tools/server/server-models.cpp` — skipping only models that are mid-request or not yet ready.
- There is **no way to protect a model.** The `pin` preset key ("do not unload this model if
  models_max is exceeded") is *commented out* in `common/arg.cpp`.
- `last_used` is refreshed on every proxied **POST** (`proxy_request(..., update_last_used=true)`;
  `proxy_get` passes `false`, so `/slots` and `/metrics` polling is harmless — the RGB daemon is
  not a factor).

So the high-frequency POST callers — `summarize()` and `tab_autoname()` in
`variants/shared/_ai_tools.sh`, which fire on every herdr tab rename — kept the small model
permanently freshest and made the largest resident model the eviction victim during any idle gap
in a coding session. A tab title cost a multi-minute reload of qwen3.8.

Lowering `--models-max` does **not** fix this; it makes it worse, by turning a memory problem
into constant reload thrash. And at capacity the router does not fail fast, it *queues*
(`join()`: "models_max reached, request … queued at position"), so with `-to 3600` and a client
that has disabled its own timeout the symptom is an indefinite hang rather than a clean 503.

The fix is to take that traffic off the router entirely:

```bash
# ~/models/cheap holds symlinks, not copies. The mmproj sidecar is deliberately
# NOT linked: llama.cpp disables prefix cache reuse on any multimodal model, and
# this tier wants that reuse far more than it wants vision.
mkdir -p ~/models/cheap/gemma-4-E2B-it
ln -s ~/models/light/gemma-4-E2B-it-GGUF/gemma-4-E2B-it-Q4_K_M.gguf \
      ~/models/cheap/gemma-4-E2B-it/
```

The directory name **is** the model id, and `gemma-4-E2B-it` is exactly
`SUMMARIZE_MODEL`'s default, so `_ai_resolve_model()` takes its exact-match branch instead of
the case-insensitive substring fallback that exists to paper over the Linux/macOS naming split.

`variants/archlinux/profile.sh` exports `AI_LLAMA_URL=http://127.0.0.1:7071`; `_ai_url()`
resolves it at call time, so no shell helper needed a code change. It is set in the archlinux
profile rather than the shared one on purpose — the macOS box runs a single router and no cheap
tier, so there `AI_LLAMA_URL` stays unset and `_ai_url()` falls back to `LOS_URL` on :7070.

Two rules to keep this working:

1. **Do not add this port as an opencode or pi provider**, and do not point a fan-out subagent
   loop at the light tier's small models. Either move puts the eviction race back.
2. `gemma-4-E2B` stays present in `~/models/light` (auto-discovered from `--models-dir` with the
   `[*]` defaults) so the vision path still works there. Only its text weights are symlinked into
   the cheap tier.

Measured on the first cold start: 12s from request to completion including the ~3 GiB load —
comfortably inside `SUMMARIZE_TIMEOUT` (60s) and opencode's 300s `headerTimeout` default.

### Presets

`llamacpp/archlinux/light.ini` and `llamacpp/archlinux/heavy.ini`. Keys are CLI args without leading dashes;
short forms (`c`, `ngl`) and env-var names (`LLAMA_ARG_*`) work too. Precedence: router CLI args >
model section > `[*]` global section.

```ini
; llamacpp/archlinux/light.ini
version = 1

[*]
ngl = 999
fa = on
jinja = true
c = 65536
np = 2

[Qwen3-Coder-Next-UD-Q4_K_XL]
c = 262144
np = 2
```

```ini
; llamacpp/archlinux/heavy.ini
version = 1

[*]
ngl = 999
fa = on
jinja = true
no-warmup = true          ; large models hit allocator failures during warmup

[DeepSeek-V4-Flash-chat-v2]
c = 32768                 ; start here, then size up per Phase 2
np = 1
cache-type-k = q8_0
cache-type-v = q8_0       ; must equal k for deepseek4/MLA
```

Section names must match the ids the router assigns, so confirm against `GET /v1/models` rather than
guessing from filenames. Three keys are preset-only and not CLI args: `load-on-startup`,
`stop-timeout` (seconds before force-kill on unload, default 10), `dedup-cache-models`.

**Implemented**: the light tier runs as a systemd **user** service
(`~/.config/systemd/user/llama-router.service`, `WantedBy=default.target`), so hours-long loops
survive terminal exit. Installed by `llamacpp/archlinux/install.sh` (called from
`variants/archlinux/setup.sh`), which skips itself if `llama-server` has not been built yet. The
unit sets `CPUQuota=90%` by default — leaves headroom for the desktop during CPU-side work (warmup,
tokenization, anything not offloaded to the GPU). It also passes `--threads`/`--threads-batch` at
half of `nproc` by default, capping ggml's own thread pool the same way CPUQuota caps the cgroup.
Override either with `LOS_CPU_QUOTA=<percent>` / `LOS_THREADS=<n>` `bash
llamacpp/archlinux/install.sh` to re-render, or `systemctl --user edit
llama-router.service` to override `CPUQuota=` directly without touching the tracked template. The
same `LOS_THREADS` default applies to the manual `los`/`los-heavy` launchers in `_llama.sh`. The
heavy tier stays a manual `los-heavy` invocation, never a service, since it is mutually exclusive
with the light tier on :7070.

## Phase 2 — Size the context for a 90.9 GiB model

Budget: 125.08 GiB total, ~113 GiB free at idle, minus 90.9 GiB of weights → roughly **14–20 GiB**
for KV cache, compute buffers, and the Hyprland session. The old `LOS_CTX=131072 --parallel 2`
default was sized against a 27B model (~23.6 GiB GTT, per the existing comment in `_llama.sh`) and
will not survive here.

Measure, then write the result into `heavy.ini`:

1. Start at `c = 32768`, `np = 1`, with `no-warmup = true`. If RADV throws _"requested buffer size
   exceeds device memory allocation limit"_, set `GGML_VK_FORCE_MAX_ALLOCATION_SIZE=4294967295` —
   4 GiB is RADV's ceiling and going above it fails differently.
2. Read `llama_kv_cache: … KV buffer size` and `common_memory_breakdown_print` from the child's log,
   divide by 32768 for GiB/token, then scale `c` to fill the budget leaving ~8 GiB of desktop
   headroom.
3. **KV quant constraint:** `src/llama-context.cpp:3591` rejects `type_k != type_v` for MLA /
   `DEEPSEEK4`. Quantize both or neither; the asymmetric split some guides suggest will refuse to
   start.
4. Keep `np` and `c` moving together. `np` divides `c` between slots, and leaving it unset lets
   llama-server pick 4 slots that each advertise the full `c` while sharing it — concurrent agent
   requests then starve the cache and get a 500 `Context size has been exceeded.` that also wipes
   every active slot's prompt cache. (This is the reasoning already documented in `_llama.sh`; it
   applies per-child in router mode.)
5. Leave mmap at default for the first load. `--mmap 0` is often recommended for Strix Halo, but at
   90.9 GiB of 125 GiB a non-mmap load risks a transient double-copy. Watch `free -g` buff/cache and
   `mem_info_vram_used` during load; only switch if load time is unacceptable. With
   `zswap.enabled=0` and 250 GiB of disk swap, any spill becomes thrash, not slowdown.

## Phase 3 — Speculative decoding (biggest speed win; do before backend tuning)

Set these as preset keys so they apply per model rather than per launch.

- **DSpark/DFlash sidecar for DeepSeek V4 Flash.** Auto-discovery only fires for HF-cache-resolved
  models, and this one is a local file, so both keys are required: `model-draft = /abs/path` plus
  `spec-type = <name>`. Get the accepted type strings from `llama-server --help | grep -A3 spec-type`
  rather than guessing; `dspark` outranks `dflash` when both exist (`common/arg.cpp:552`). Sharded
  drafts _need_ an explicit `spec-type`, since inference only reads the first split's metadata
  (`common/arg.cpp:565`).
- **Ngram speculation needs no draft model at all** — a free win on coding loops, where output
  re-emits large spans of the prompt: `spec-ngram-mod-n-max`, `spec-ngram-mod-n-match`,
  `spec-ngram-simple-size-n` / `-m`. Try it in the `[*]` section of _both_ INIs.
- Tune `spec-draft-p-min` / `spec-draft-n-max` against the acceptance counters the server exports:
  `llamacpp:spec_decode_num_draft_tokens_total` vs `…_num_accepted_tokens_total` on
  `GET /metrics?model=<name>`. Keep speculation only where acceptance beats baseline.

## Phase 4 — Second build: HIP + rocWMMA

Keep `build/` (Vulkan) and add `build-hip/` so backends can be A/B'd without rebuilding. ROCm is
**not** installed system-wide — it used to be reachable only via ollama's bundled `rocm_v7_2`, and
with ollama retired there is no ROCm on the box at all — so this pulls a large SDK (Arch `extra`
currently carries 7.2.4, including `rocwmma`):

```bash
sudo pacman -S rocm-hip-sdk hipblas rocblas hipblaslt
cmake -S ~/dev/llama.cpp -B ~/dev/llama.cpp/build-hip \
  -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1151 -DGGML_HIP_ROCWMMA_FATTN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build ~/dev/llama.cpp/build-hip -j
```

- `GGML_HIP_ROCWMMA_FATTN=ON` is what produces the long-context win; without it ROCm isn't worth the
  disk space.
- Test `GGML_HIP_NO_VMM` both ways. One Strix Halo writeup needed `-DGGML_HIP_NO_VMM=OFF` to reach
  GTT, then needed `--no-warmup` to survive the VMM allocator. Ollama's bundled build runs
  `NO_VMM = 1` and still saw 62.5 GiB — confirming that cap is the kernel's, not this flag's.
- Watch for **llama.cpp #17917**, a ROCm 7.x prompt-processing regression on Strix Halo (you'd be on
  7.2.4). If measured pp at depth doesn't beat Vulkan, that's why — stay on Vulkan and revisit.
- A router runs **one binary**, so per-model backend choice isn't a preset key. Mixing backends means
  two routers on two ports (`LLAMA_CPP_BUILD=~/dev/llama.cpp/build-hip LOS_PORT=7072 los-heavy`), not
  two presets.

## Phase 5 — Model set

Download into the tier directories under `~/models/` with
`llamacpp/archlinux/fetch-models.sh`.

**Every GGUF under `~/models` must have a line in that script.** It did not used to, and the
gap was invisible: `qwen3.8` — the default model for `opencode`'s `model`/`small_model`, four of
its agents, and pi's `defaultModel` — existed only as a **hardlink out of ollama's blob store**
(`find -links +1` shows the two shared inodes). Retiring ollama would have left no recipe for the
most important model on the box. `bin/llamacpp-audit` now enforces the invariant.

Two standing exceptions:

- **`qwen3.8` is fetched with `fetch_dir_model`, not `fetch`.** The pair on this box is
  ollama-derived (plain `Q4_K_M` named `qwen3.8-Q4_K_M.gguf`, 16810714464 bytes, projector
  931146016) where the recipe yields unsloth's `UD-Q4_K_M` and a 927607488-byte projector. Plain
  `fetch` would see both size mismatches and replace a working, self-consistent pair — and a
  second model GGUF in that directory would make the id resolve nondeterministically, since
  `scan_subdir()` takes whichever non-`mmproj` GGUF it iterates last. The guard skips the whole
  directory when it already holds a model. A fresh machine gets the unsloth pair; the id is
  `qwen3.8` either way, because it is the directory name.
- **DeepSeek V4 Flash has no recipe and cannot have one.** It is a hand-tuned mixed quant built
  against a custom imatrix, not a published artifact. It is the only file here a disk failure
  would lose permanently — back it up separately.

The **heavy tier is opt-in** (`LOS_FETCH_HEAVY=1`), because neither of its two files is currently
on disk and an unguarded `fetch` would make every routine re-run start a 64 GB download.


| Tier            | Model                                     | Quant                   | Size     | Expected                       | Role                                                                                                                                   |
| --------------- | ----------------------------------------- | ----------------------- | -------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| **Workhorse**   | `gpt-oss-120b` (117B-A5.1B)               | MXFP4                   | ~63 GB   | ~55 t/s tg                     | Default chat + agentic coding; best capability-per-token-rate here. Goes in `heavy/`.                                                   |
| ~~Loop engine~~ | ~~`unsloth/Qwen3-Coder-Next-GGUF`~~       | —                       | —        | —                              | **Removed.** `c901081` deleted the file and its `light.ini` section but left `generate-code` pointing at it; the router then held a child with `--alias` and no `--model`, stuck `loading` forever and — since `pick_victim()` skips models that are not ready — permanently holding one of five `--models-max` slots. `generate-code` now targets GLM-4.7-Flash. |
| **Next arch**   | `unsloth/Qwen3.8-Flash-Next-GGUF` (125B+51B-A6B) | UD-IQ4_XS        | ~87 GiB  | TBD (6B active)                | Qwen4-preview arch: Gated DeltaNet + QSA hybrid attention, text-only (no mmproj). Needs llama.cpp PR #27742 before it loads.         |
| **Fan-out**     | `GLM-4.7-Flash` (30B class)               | UD-Q4_K_XL              | 16.32 GiB | 60–100 t/s                    | Cheap parallel subagents, quick tool calls; what opencode's `generate-code` subagent targets. Needs `kv-unified` — see below.           |
| **Capability**  | existing DeepSeek V4 Flash 284B-A13B      | custom IQ2_XXS/Q4_K mix | 90.9 GiB | ~13 t/s, more with speculation | Hard planning/architecture steps only — ~155 t/s prefill means a 20k-token turn costs ~2 min before the first token. Not a loop engine. |

Middle sizes are estimates from parameter count; DeepSeek and GLM are measured off disk.

### Per-slot context is not `--ctx-size`

`--ctx-size` sizes the whole KV **pool**. Without `--kv-unified` the router splits it across
`--parallel` slots, so one conversation gets `c/np`, and llama.cpp caps a slot there
(`server-context.cpp`, `llama_n_ctx_seq`). Under `--kv-unified` there is one shared pool and
every slot's `n_ctx_slot` is the full `c`, at the same total allocation.

This matters because clients advertise a context window, and advertising more than a slot
actually gets fails with `ERROR_TYPE_EXCEED_CONTEXT_SIZE` partway through a conversation rather
than refusing up front. Two ways it went wrong here:

- `bin/llamacpp-sync` derived pi's `contextWindow` straight from `--ctx-size`, overstating every
  model by a factor of `np`. It now computes the per-slot value (`per_slot_context()`).
- Raising `np` on a section without adding `kv-unified` silently divides the per-slot ceiling.
  `[GLM-4.7-Flash-UD-Q4_K_XL]` at `c=131072, np=4` yields 32768/slot, well under the 65536
  opencode advertises and the 131072 pi advertises — hence `kv-unified = true` on that section.

`bin/llamacpp-audit` checks this invariant across `light.ini`/`cheap.ini`/`heavy.ini` and both
client configs, including models with no INI section that inherit `[*]` via `--models-dir`.

## Phase 6 — Clients: picking a model on the fly

The router's model id is the only handle you need. Get the exact ids first — everything below uses
them verbatim:

```bash
curl -s localhost:7070/v1/models | jq -r '.data[].id'
```

Ids come from the directory/preset entry name, not the filename, so check rather than guess.

### curl / any OpenAI-compatible client

The model is a normal request field — no restart, no reconfiguration:

```bash
curl -s localhost:7070/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "Qwen3-Coder-Next-UD-Q4_K_XL",
  "messages": [{"role":"user","content":"hello"}],
  "cache_prompt": true
}'
```

- **GET endpoints take it as a query param instead**, URL-encoded:
  `curl -s 'localhost:7070/props?model=DeepSeek-V4-Flash-chat-v2'`. `/metrics` returns 400
  `model name is missing from the request` without it.
- **Autoload per request:** append `?autoload=false` to refuse loading a model that isn't resident
  (useful in a loop that must not stall for a 90 GiB load), or `?autoload=true` to force it when the
  router was started with `--no-models-autoload`.
- **Pre-load / evict explicitly** instead of waiting for the first request:
  `curl -X POST localhost:7070/models/load -d '{"model":"..."}'`, and `POST /models/unload` to free
  memory before switching tiers.

### opencode

`~/.config/opencode/opencode.json` — the keys of the `models` map _are_ the ids sent upstream, so add
one entry per router model. Reference them elsewhere as `provider/model`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llamacpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "llama.cpp",
      "options": {
        "baseURL": "http://127.0.0.1:7070/v1",
        "timeout": false,        // a 90 GiB first load outlasts the default timeout
        "headerTimeout": false
      },
      "models": {
        "Qwen3-Coder-Next-UD-Q4_K_XL": {
          "name": "Qwen3 Coder Next",
          "limit": { "context": 262144, "output": 32768 },
          "tool_call": true
        },
        "DeepSeek-V4-Flash-chat-v2": {
          "name": "DeepSeek V4 Flash",
          "limit": { "context": 32768, "output": 16384 },
          "tool_call": true,
          "reasoning": true
        }
      }
    }
  },
  "model": "llamacpp/Qwen3-Coder-Next-UD-Q4_K_XL",
  "small_model": "llamacpp/GLM-4.7-Flash-Q4_K_M"
}
```

Switching on the fly, in order of convenience: the TUI model picker, `--model
llamacpp/<id>` on the CLI, or a per-agent `model` override in the `agent` section. `small_model`
routes cheap work (title generation) to the fan-out tier — worth pointing at the smallest model so it
never wakes a big one. Note the current config's `"context": 32768` is a leftover placeholder;
correct it per model or opencode will truncate far below what the server serves.

### pi

`pi` has first-class support for exactly this setup — its docs call the endpoint "the router URL":

```
/login llama.cpp        # prompts for the router URL, default http://127.0.0.1:7070
/model                  # pick among the router's models
/llama                  # load one first, if started with --no-models-autoload
```

Or non-interactively:

```bash
export LLAMA_BASE_URL=http://127.0.0.1:7070
export LLAMA_API_KEY=noop
pi
```

`/model` reads the live model list from the router, so a model added to a preset shows up without
touching pi's config.

### herdr

`herdr` is a terminal workspace manager, not an LLM client — it starts _other_ agents in panes
(`--kind` accepts `pi`, `opencode`, `hermes`, `claude`, `codex`, …). There is no base URL or model to
configure in `config.toml`; the model comes from whichever agent runs in the pane, and per-launch
overrides pass through after `--`:

```bash
herdr agent start planner --kind pi --pane <id> -- --model DeepSeek-V4-Flash-chat-v2
```

That's the clean way to run a heavy planner in one pane and a light loop agent in another — both
against the same router, each naming its own model.

### Long sessions: resumable streaming

This is the answer to "long loops must not die". Send an `X-Conversation-Id` header on
`POST /v1/chat/completions` and the generation keeps running server-side when the socket drops —
while attached, peer disconnect is deliberately ignored and only `DELETE /v1/stream?conv_id=<id>`
stops it.

- Reattach: `GET /v1/stream?conv_id=<id>&from=N` (replays from offset N, then goes live).
- Status: `POST /v1/streams/lookup` with `{"conversation_ids": [...]}`. There is deliberately no
  listing route.
- Router mode proxies all three through a `conv_id → child` map; the id may carry a `::model` suffix
  for direct routing.

Two limits: the replay buffer is a **4 MiB ring** (oldest bytes dropped first; an offset below the
dropped prefix returns 400), and it is opt-in per request — only clients that send the header
benefit, which in practice means the custom programmatic client. Set `cache_prompt: true` there too;
for multi-turn loops prompt caching is the biggest win after speculation, since it stops re-prefilling
the whole conversation each turn.

## Verification

1. `cat /sys/class/drm/card1/device/mem_info_gtt_total` → ~128 GiB after the Phase 0 reboot.
2. `los`, then `curl -s localhost:7070/v1/models | jq -r '.data[].id'` → the light tier only, with
   **no DeepSeek entry**. That absence is the test that the directory + `LLAMA_CACHE` filtering works.
3. `killport 7070; los-heavy`, then the same call → DeepSeek present. Send it a request and confirm
   it loads. **Loading at all is the proof Phase 0 worked.** Check the child log for full offload: no
   CPU buffer for weight tensors, `llama_prepare_model_devices` reporting >100 GiB free.
4. A `/v1/chat/completions` call with a tool definition → well-formed `tool_calls` (validates
   `--jinja` against the deepseek4 template).
5. Autoload/LRU: on `los`, request two different models in sequence and watch `GET /models/sse`
   report `loading` → `loaded`, and the LRU unload once `--models-max` is hit. Confirm `free -g`
   returns to baseline after an unload.
6. On-the-fly switch: same curl twice with different `"model"` values, and an opencode session
   switching models mid-conversation without restarting the server.
7. Resumable stream: start a long generation with `X-Conversation-Id: test1`, kill the client
   mid-stream, then `GET /v1/stream?conv_id=test1&from=0` and confirm the generation continued.
8. `llama-bench -m <model> -p 512 -n 128 -fa 1 -ngl 999 -d 0 -d 32768 -d 131072` on **both** builds
   for the workhorse tier. The depth-131072 prefill row decides the default backend; record all rows.
9. Speculation A/B: same prompt with and without sidecar/ngram keys, comparing decode t/s and the
   `spec_decode_*` metrics.
10. Soak: one herdr-managed agent task for 30+ minutes, watching `free -g` and `mem_info_vram_used`
    for creep and the child log for slot/KV exhaustion — the exact failure Phase 2 step 4 describes.

## Sources

- [Strix Halo local LLM guide + benchmarks](https://hogeheer499-commits.github.io/strix-halo-guide/)
- [Strix Halo wiki — llama.cpp performance](https://strixhalo.wiki/AI/llamacpp-performance)
- [llama.cpp: Vulkan vs ROCm on Strix Halo](https://www.soothill.io/blog/2026/08/03/llamacpp-vulkan-vs-rocm-strix-halo/)
- [AMD Strix Halo backend benchmark grid](https://kyuz0.github.io/amd-strix-halo-toolboxes/)
- [llama.cpp #13024 — Vulkan allocation limit on very large models](https://github.com/ggml-org/llama.cpp/issues/13024)
- [llama.cpp #17917 — ROCm perf regression on Strix Halo](https://github.com/ggml-org/llama.cpp/issues/17917)
- [Running DeepSeek V4 Flash on AMD Strix Halo](https://tinycomputers.io/posts/running-deepseek-v4-flash-on-amd-strix-halo.html)
- [DeepSeek V4 Flash, up to 32 tok/s on Ryzen AI MAX+ 395](https://www.lucebox.com/blog/deepseek-v4-strix-halo)
- [unsloth/DeepSeek-V4-Flash-0731-GGUF](https://huggingface.co/unsloth/DeepSeek-V4-Flash-0731-GGUF)
- [Qwen3-Coder-Next technical report](https://arxiv.org/html/2603.00729v1)
- [Qwen3-Coder-Next vs gpt-oss-120b](https://artificialanalysis.ai/models/comparisons/qwen3-coder-next-vs-gpt-oss-120b)
- [pi — llama.cpp integration docs](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/llama-cpp.md)
- [opencode config schema](https://opencode.ai/config.json)

Router-mode specifics above are read from this checkout: `tools/server/README.md` ("Using multiple
models"), `tools/server/README-dev.md` ("Resumable streaming"), and
`tools/server/server-models.{h,cpp}`.
