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

# Router mode: no -m, so llama-server loads nothing itself and forks one child
# process per model, routed on the JSON body's "model" field. See
# ryzen-llm-setup.md Phase 1 for the directory-split rationale (--models-max counts
# models, not bytes, so the big DeepSeek-class weights live in a separate "heavy"
# tier directory/preset that is never enumerated alongside the light tier).
#
# Two of the three tiers are persistent systemd --user services with a CPUQuota
# (llamacpp/archlinux): light on :8080 and cheap on :8081. This manual launcher is for
# the "heavy" tier (never a service, one model at a time) and for ad-hoc runs of the
# other two outside their units, e.g. on a different LOS_PORT.
_los_router() {
  local tier="$1" max="$2"; shift 2
  local half_cores=$(( $(nproc) / 2 ))
  ((half_cores < 1)) && half_cores=1
  ensure_llama_cpp || return 1
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

# Small/medium models, up to 5 resident -- matches llama-router.service's --models-max
# so a foreground run behaves like the unit. DeepSeek-class is excluded by directory.
# Use this for a foreground/ad-hoc run (`killport 8080` first if the service owns :8080).
los() { _los_router light 5 "$@"; }

# One model at a time, the big ones. Mutually exclusive with `los` and the systemd
# service on :8080 -- `killport 8080` before switching tiers, or pass LOS_PORT.
los-heavy() { _los_router heavy 1 "$@"; }

# The cheap tier on :8081, mirroring llama-router-cheap.service. This exists to keep
# high-frequency shell traffic (summarize/tab_autoname, see variants/shared/_ai_tools.sh)
# off the light router: eviction there is pure LRU on last_used with NO pinning -- the
# `pin` preset key is commented out in llama.cpp's common/arg.cpp -- and every proxied
# request refreshes the target's timestamp. A tab-title call every few seconds therefore
# keeps the small model freshest and makes the ~28 GiB qwen3.8 the eviction victim during
# any idle gap. Separate port, separate LLAMA_CACHE, one model resident.
los-cheap() { LOS_PORT="${LOS_PORT:-8081}" _los_router cheap 1 "$@"; }
