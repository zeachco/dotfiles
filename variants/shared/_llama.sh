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

alias los='llama-ollama-server'
