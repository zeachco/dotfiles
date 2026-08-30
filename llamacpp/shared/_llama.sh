LLAMA_CPP_BUILD="$HOME/dev/llama.cpp/build"

ensure_llama_cpp() {
  local llama_cpp_dir="$HOME/dev/llama.cpp"

  if [[ -x "$LLAMA_CPP_BUILD/bin/llama-server" ]]; then
    return 0
  fi

  if [[ ! -d "$llama_cpp_dir/.git" ]]; then
    mkdir -p "$HOME/dev" || return 1
    git clone git@github.com:ggml-org/llama.cpp.git "$llama_cpp_dir" || return 1
  fi

  echo "llama.cpp needs to be built first with make before it can be used as a server." >&2
  return 1
}

LOS_CONF_DIR="${LOS_CONF_DIR:-$HOME/dotfiles/llamacpp/archlinux}"

llama-ollama-server() {
  local model
  local from

  ensure_llama_cpp || return 1

  model="$(ollama list | tail -n +2 | awk '{print $1}' | fzf --prompt='Ollama model: ')" || return
  from="$(ollama show "$model" --modelfile | awk '$1 == "FROM" { sub(/^FROM[[:space:]]+/, ""); print; exit }')"

  if [[ -z "$from" ]]; then
    echo "Could not find the model blob for: $model" >&2
    return 1
  fi

  if [[ "$from" == /* ]]; then
    GGUF="$from"
  else
    GGUF="${OLLAMA_MODELS:-$HOME/.ollama/models}/blobs/${from/:/-}"
  fi

  if [[ ! -f "$GGUF" ]]; then
    echo "Model blob does not exist: $GGUF" >&2
    return 1
  fi

  export GGUF
  echo "Starting $model from $GGUF"

  # An explicit --parallel is deliberate: left unset, llama-server picks 4 slots with a
  # unified KV cache, where every slot advertises the full -c but they all share it.
  # Concurrent agent requests then starve the cache and get a 500
  # "Context size has been exceeded." that also wipes every active slot's prompt cache.
  #
  # --parallel divides -c between slots, so the two move together: 131072/2 = 65536 per
  # slot. Measured ~23.6 GiB GTT for Qwen3.8 27B, whose hybrid attention costs only
  # ~64 KiB/token. Raise both for more concurrency (262144/4 is also 65536 per slot).
  "$LLAMA_CPP_BUILD/bin/llama-server" \
    -m "$GGUF" \
    -ngl 999 \
    -fa on \
    --jinja \
    -c "${LOS_CTX:-131072}" \
    --parallel "${LOS_PARALLEL:-2}" \
    --port 8080
}

alias los-pick='llama-ollama-server'

# A 90.9 GiB load cannot share memory with a resident ollama runner, and the unit
# keeps models for 30m (OLLAMA_KEEP_ALIVE) across 3 slots (OLLAMA_MAX_LOADED_MODELS).
_los_free_memory() {
  ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | while read -r m; do
    [[ -n "$m" ]] && ollama stop "$m"
  done
}

# Router mode: no -m, so llama-server loads nothing itself and forks one child
# process per model, routed on the JSON body's "model" field. See
# ryzen-llm-setup.md Phase 1 for the directory-split rationale (--models-max counts
# models, not bytes, so the big DeepSeek-class weights live in a separate "heavy"
# tier directory/preset that is never enumerated alongside the light tier).
#
# The persistent systemd --user service (llamacpp/archlinux) already
# runs this same "light" invocation with a CPUQuota; this manual launcher is for the
# "heavy" tier (never a service, one model at a time) and for ad-hoc light-tier runs
# outside the unit, e.g. with a different LOS_PORT.
_los_router() {
  local tier="$1" max="$2"; shift 2
  local half_cores=$(( $(nproc) / 2 ))
  ((half_cores < 1)) && half_cores=1
  ensure_llama_cpp || return 1
  _los_free_memory
  LLAMA_CACHE="$HOME/.cache/llama.cpp-$tier" \
    "$LLAMA_CPP_BUILD/bin/llama-server" \
      --models-dir "$HOME/models/$tier" \
      --models-preset "$LOS_CONF_DIR/$tier.ini" \
      --models-max "$max" \
      --host 127.0.0.1 --port "${LOS_PORT:-8080}" \
      -to 3600 \
      --threads "${LOS_THREADS:-$half_cores}" \
      --threads-batch "${LOS_THREADS:-$half_cores}" \
      "$@"
}

# Small/medium models, up to 4 resident. DeepSeek-class is excluded by directory.
# Duplicates the systemd unit's ExecStart -- use this for a foreground/ad-hoc run
# (`killport 8080` first if the service already owns :8080).
los() { _los_router light 4 "$@"; }

# One model at a time, the big ones. Mutually exclusive with `los` and the systemd
# service on :8080 -- `killport 8080` before switching tiers, or pass LOS_PORT.
los-heavy() { _los_router heavy 1 "$@"; }
