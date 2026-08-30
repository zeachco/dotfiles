# Local LLM setup — Ryzen AI MAX+ 395 (Strix Halo, 128 GiB)

Runbook for AMD Ryzen AI MAX+ 395 / Radeon 8060S (gfx1151), 128 GiB unified memory,
Omarchy 4.0, Limine + measured UKI.

Priorities this setup optimizes for, in order: **flexibility** (switch models freely, experiment with
small ones, still able to run the big ones), **stability** (long autonomous loops must not time out
or die), then speed.

## Where things stand

- `~/dev/llama.cpp` @ `b10524-22-g0e1d9185c`, built in `build/` with **`GGML_VULKAN=ON`,
  `GGML_HIP=OFF`** — Vulkan only.
- `llamacpp/shared/_llama.sh` defines `llama-ollama-server` (`los`): fzf-picks an `ollama list`
  entry, resolves its blob via `ollama show --modelfile`, exports `$GGUF`, starts `llama-server` on
  :8080 with `-ngl 999 -fa on --jinja -c ${LOS_CTX:-131072} --parallel ${LOS_PARALLEL:-2}`.
- `~/models/DeepSeek-V4-Flash-chat-v2/…-chat-v2-imatrix-fixed.gguf` — **90.9 GiB** hand-tuned mixed
  quant (layers 37–42 experts Q4_K, other expert layers IQ2_XXS gate/up, Q2_K down,
  attn-proj/shared-experts/output Q8). `general.architecture = deepseek4`.
- `ollama` 0.32.14 (`/usr/local/bin`, hand-installed), 91 GB of models, running the **ROCm** backend
  and refusing Vulkan: `dropping integrated GPU; to enable, set OLLAMA_IGPU_ENABLE=1`.
- `~/.config/opencode/opencode.json` points a `llamacpp` provider at `http://127.0.0.1:8080/v1` but
  declares `"context": 32768` — a quarter of what `los` actually serves.

## The four findings that drive this runbook

1. **The GPU can only address 62.5 GiB, so the 90.9 GiB DeepSeek cannot load at all.** Ollama logs
   it: `library=ROCm compute=gfx1151 type=iGPU total="62.5 GiB"`, and `mem_info_gtt_total` = 67152236544. That's the default GTT cap, not a memory shortage. BIOS UMA is already at the ideal
   512 MB (`mem_info_vram_total` = 536870912), so it's a one-line kernel-cmdline fix. **Nothing else
   here matters until Phase 0 is done.**
2. **`llama-server` has a built-in router mode, already present in this build**
   (`tools/server/server-models.cpp`). It serves many models from one port, autoloads on demand,
   isolates each model in a child process, and supports resumable SSE streams. This replaces both the
   fzf-relaunch flow and any need for llama-swap — see Phase 1.
3. **`los` can't see the DeepSeek model anyway** — it enumerates `ollama list` only, and a 90.9 GiB
   hand-quant will never be in ollama's registry.
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

## Phase 0 — Unlock GTT (reboot; blocks everything)

Cmdline lives in `/etc/kernel/cmdline` (Limine + UKI, not GRUB).

```bash
# append to the existing crypt/root/btrfs args:
#   amdgpu.gttsize=131072 ttm.pages_limit=31457280
sudo $EDITOR /etc/kernel/cmdline
sudo limine-update
# reboot, then:
cat /sys/class/drm/card1/device/mem_info_gtt_total   # expect ~128 GiB, not 67152236544
```

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

**Implemented** in `llamacpp/shared/_llama.sh`. The existing fzf function was renamed to `los-pick`,
kept as a one-off flag-experiment tool, since `los` is now the router.

```bash
LOS_CONF_DIR="${LOS_CONF_DIR:-$HOME/dotfiles/llamacpp/archlinux}"

# A 90.9 GiB load cannot share memory with a resident ollama runner, and the unit
# keeps models for 30m (OLLAMA_KEEP_ALIVE) across 3 slots (OLLAMA_MAX_LOADED_MODELS).
_los_free_memory() {
  ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | while read -r m; do
    [[ -n "$m" ]] && ollama stop "$m"
  done
}

_los_router() {
  local tier="$1" max="$2"; shift 2
  ensure_llama_cpp || return 1
  _los_free_memory
  LLAMA_CACHE="$HOME/.cache/llama.cpp-$tier" \
    "$LLAMA_CPP_BUILD/bin/llama-server" \
      --models-dir "$HOME/models/$tier" \
      --models-preset "$LOS_CONF_DIR/$tier.ini" \
      --models-max "$max" \
      --host 127.0.0.1 --port "${LOS_PORT:-8080}" \
      -to 3600 \
      "$@"
}

# Small/medium models, up to 4 resident. DeepSeek-class is excluded by directory.
los() { _los_router light 4 "$@"; }

# One model at a time, the big ones.
los-heavy() { _los_router heavy 1 "$@"; }
```

Both bind :8080 so client config stays fixed — they are mutually exclusive. `killport 8080` (already
in `profile.sh`) before switching tiers, or pass `LOS_PORT` to run one alongside the other. Extra
args pass straight through, and children inherit the router's argv _and_ environment, so
`GGML_VK_FORCE_MAX_ALLOCATION_SIZE=… los-heavy` works as expected.

Separate `LLAMA_CACHE` per tier is what stops an `-hf` pull in one tier from showing up in the other.

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
with the light tier on :8080.

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
**not** installed system-wide (ollama ships its own bundled `rocm_v7_2`), so this pulls a large SDK:

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
  two routers on two ports (`LLAMA_CPP_BUILD=~/dev/llama.cpp/build-hip LOS_PORT=8081 los-heavy`), not
  two presets.

## Phase 5 — Model set

Download into the tier directories under `~/models/` (481 GB free).

| Tier            | Model                                     | Quant                   | Size     | Expected                       | Role                                                                                                                                   |
| --------------- | ----------------------------------------- | ----------------------- | -------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| **Workhorse**   | `gpt-oss-120b` (117B-A5.1B)               | MXFP4                   | ~63 GB   | ~55 t/s tg                     | Default chat + agentic coding; best capability-per-token-rate here. Goes in `heavy/`.                                                   |
| **Loop engine** | `unsloth/Qwen3-Coder-Next-GGUF` (80B-A3B) | UD-Q4_K_XL              | ~45 GB   | ≫55 t/s (3B active)            | Hours-long autonomous loops, 256k ctx, 70.6% SWE-bench Verified.                                                                       |
| **Next arch**   | `unsloth/Qwen3.8-Flash-Next-GGUF` (125B+51B-A6B) | UD-IQ4_XS        | ~87 GiB  | TBD (6B active)                | Qwen4-preview arch: Gated DeltaNet + QSA hybrid attention, text-only (no mmproj). Needs llama.cpp PR #27742 before it loads.         |
| **Fan-out**     | `GLM-4.7-Flash` (30B class)               | Q4_K_M                  | ~19 GB   | 60–100 t/s                     | Cheap parallel subagents, quick tool calls. Good `los` companion.                                                                      |
| **Capability**  | existing DeepSeek V4 Flash 284B-A13B      | custom IQ2_XXS/Q4_K mix | 90.9 GiB | ~13 t/s, more with speculation | Hard planning/architecture steps only — ~155 t/s prefill means a 20k-token turn costs ~2 min before the first token. Not a loop engine. |

Middle two sizes are estimates from parameter count; the DeepSeek figure is measured off disk.

## Phase 6 — Clients: picking a model on the fly

The router's model id is the only handle you need. Get the exact ids first — everything below uses
them verbatim:

```bash
curl -s localhost:8080/v1/models | jq -r '.data[].id'
```

Ids come from the directory/preset entry name, not the filename, so check rather than guess.

### curl / any OpenAI-compatible client

The model is a normal request field — no restart, no reconfiguration:

```bash
curl -s localhost:8080/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "Qwen3-Coder-Next-UD-Q4_K_XL",
  "messages": [{"role":"user","content":"hello"}],
  "cache_prompt": true
}'
```

- **GET endpoints take it as a query param instead**, URL-encoded:
  `curl -s 'localhost:8080/props?model=DeepSeek-V4-Flash-chat-v2'`. `/metrics` returns 400
  `model name is missing from the request` without it.
- **Autoload per request:** append `?autoload=false` to refuse loading a model that isn't resident
  (useful in a loop that must not stall for a 90 GiB load), or `?autoload=true` to force it when the
  router was started with `--no-models-autoload`.
- **Pre-load / evict explicitly** instead of waiting for the first request:
  `curl -X POST localhost:8080/models/load -d '{"model":"..."}'`, and `POST /models/unload` to free
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
        "baseURL": "http://127.0.0.1:8080/v1",
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
/login llama.cpp        # prompts for the router URL, default http://127.0.0.1:8080
/model                  # pick among the router's models
/llama                  # load one first, if started with --no-models-autoload
```

Or non-interactively:

```bash
export LLAMA_BASE_URL=http://127.0.0.1:8080
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
2. `los`, then `curl -s localhost:8080/v1/models | jq -r '.data[].id'` → the light tier only, with
   **no DeepSeek entry**. That absence is the test that the directory + `LLAMA_CACHE` filtering works.
3. `killport 8080; los-heavy`, then the same call → DeepSeek present. Send it a request and confirm
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
