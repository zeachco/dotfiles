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

  "$LLAMA_CPP_BUILD/bin/llama-server" \
    -m "$GGUF" \
    -ngl 999 \
    -fa on \
    --jinja \
    -c 32768 \
    --port 8080
}

alias los='llama-ollama-server'
