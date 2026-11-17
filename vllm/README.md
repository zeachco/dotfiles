# vllm/

Local model serving with [vLLM](https://docs.vllm.ai). It runs **beside** llama.cpp
(`llamacpp/`), not in place of it. llama.cpp stays the default until vLLM is proven.

Only the Apple Silicon Mac has a vLLM setup. It uses
[vllm-metal](https://github.com/vllm-project/vllm-metal), the plugin that runs vLLM on
MLX and Metal. The Strix Halo box has no vLLM setup: vLLM has no Vulkan backend, and
ROCm on that chip works only with community builds.

## Layout

| Path                         | What it is                                                                 |
| ---------------------------- | -------------------------------------------------------------------------- |
| `osx/setup.sh`               | Hardware gate, `brew install vllm-metal`, then `install.sh`. Downloads no model |
| `osx/install.sh`             | Installs the launchd user agent `com.zeachco.vllm` (no-op if nothing changed) |
| `osx/com.zeachco.vllm.plist` | The agent template                                                         |
| `osx/models.conf`            | The model list: `id \| source \| vllm serve arguments`                     |
| `osx/vllm-ctl`               | The control command (alias `vllm-ctl`), and what the agent runs            |

## How it is different from the llama.cpp router

| | llama.cpp router | vLLM |
| --- | --- | --- |
| Models for each server | Many (one child process for each model) | **One** |
| Load a model | `los`, or the first request (Mac) | `vllm-ctl use <id>` restarts the server |
| Endpoint | `:7070`, LAN | `127.0.0.1:8000`, loopback only |
| Weights | GGUF in `~/models` | MLX repositories in the HuggingFace cache |
| Context | `c / np` slots | One paged KV pool. A request that does not fit waits |
| Presets | `osx.ini` | `osx/models.conf` |

## Use

```sh
vllm-ctl models            # the list, with "on disk" and the active model
vllm-ctl fetch Qwen3.8-27B # download one model (asks first)
vllm-ctl use Qwen3.8-27B   # start the server with this model, wait for /health
vllm-ctl status
vllm-ctl logs
vllm-ctl stop              # stop the server, give the memory back
```

The agent is idle after install. It uses no memory until `vllm-ctl use <id>`. The
active model id is machine state (`~/.local/state/vllm/active`), so the same model
comes back at the next login. `vllm-ctl stop` clears it.

`vllm-ctl use` also runs `llamacpp-sync --provider vllm`. The `vllm` provider in pi
and opencode then lists the one model that the server holds.

## Rules

- **The server never downloads.** The agent sets `HF_HUB_OFFLINE=1`, and
  `vllm-ctl serve` refuses a model that is not on disk. Without this, `vllm serve`
  downloads a missing repository (tens of GB) with no question. `vllm-ctl fetch <id>`
  is the only command that downloads. `setup.sh` does not call it.
- **Memory is shared with llama.cpp.** The two servers do not know about each other.
  Before you start a large model here, unload the llama.cpp models (`los` -> drain).
- **`--gpu-memory-utilization` is a ceiling, not a reservation.** vllm-metal allocates
  the KV pool lazily. Two servers sized against the same free memory can both claim
  it.
- **A start failure does not loop.** If `vllm serve` exits before `/health` answers
  (a wrong argument, a KV cache that does not fit), `vllm-ctl serve` reports exit 0 and
  launchd leaves the job stopped. `vllm-ctl use` prints the error lines from the log.
  A crash after the server was healthy is restarted by launchd.
- **A stop kills the full process tree.** `vllm serve` forks an engine process, and a
  SIGTERM during startup left the tree alive. `vllm-ctl serve` stays the parent, passes
  the signal on, and then kills its process group.
- **The memory fraction is cut down to the free memory.** With llama.cpp holding
  Qwen3.8-27B, the 0.6B test model got 2.71 GiB of KV cache at 0.2 and 3.3 GiB at 0.3.
  A larger fraction does not help on a full box: unload the llama.cpp model.
- **The values in `models.conf` are not measured yet.** They come from the llama.cpp
  presets. Measure after the first real load and correct them there.

## Models

`models.conf` has the daily models as MLX 4-bit repositories, and one small test model
that is already in the HF cache. The ids are the same as the llama.cpp ids where the
model is the same.

A source can also be a local `.gguf` file. vllm-metal reads GGUF for the Qwen2, Qwen3,
Llama, Mistral and Qwen3.5 (`qwen35`) families, with `--tokenizer <repo>` for the
config and tokenizer. This is not used here:

- IQ4_XS weights need about twice their file size in memory, and `Qwen3.8-27B` on
  this Mac is an IQ4_XS file.
- Gemma and GLM (MLA) GGUF files are not supported.
- GGUF models are text only.

## Update

```sh
brew update && brew upgrade vllm-metal
vllm-ctl restart
```

`setup.sh` installs vllm-metal but does not upgrade it. Homebrew refuses a formula
from an untrusted tap, so `setup.sh` trusts this one formula
(`brew trust --formula vllm-project/vllm-metal/vllm-metal`), not the full tap.
