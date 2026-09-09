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
# (llamacpp/archlinux): light on :7070 and cheap on :7071. This manual launcher is for
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
      --host 127.0.0.1 --port "${LOS_PORT:-7070}" \
      -to 3600 \
      --threads "${LOS_THREADS:-$half_cores}" \
      --threads-batch "${LOS_THREADS:-$half_cores}" \
      "$@"
}

# Small/medium models, up to 5 resident -- matches llama-router.service's --models-max
# so a foreground run behaves like the unit. DeepSeek-class is excluded by directory.
# Use this for a foreground/ad-hoc run (`killport 7070` first if the service owns :7070).
los() { _los_router light 5 "$@"; }

# One model at a time, the big ones, on :7072 -- mirroring llama-router-heavy.service.
# No longer mutually exclusive with `los` by PORT, but still by MEMORY: the routers do
# not coordinate, so with qwen3.8 + GLM resident on :7070 an 87 GiB load here fails on
# the GPU. `los-drain` first. See ryzen-llm-setup.md "The heavy tier".
los-heavy() { LOS_PORT="${LOS_PORT:-7072}" _los_router heavy 1 --no-models-autoload "$@"; }

# Load a heavy-tier model explicitly (the heavy router runs --no-models-autoload, so a
# request for an unloaded model is refused with 400 "model is not loaded" instead of
# pulling ~90 GiB under someone's feet). Pair with los-drain. Inside pi the same thing is
# `/login llama.cpp` once with http://127.0.0.1:7072, then `/llama`.
#   los-load                      # list what :7072 has and what is loaded
#   los-load Qwen3.8-Flash-Next   # load it, wait until ready
los-load() {
  local url="${LOS_HEAVY_URL:-http://127.0.0.1:7072}" model="${1:-}"
  if [[ -z "$model" ]]; then
    curl -sf -m 5 "$url/v1/models" | python3 -c 'import sys,json
for m in json.load(sys.stdin).get("data",[]):
    st=m.get("status"); print(f"  {m["id"]:40s} {st.get("value") if isinstance(st,dict) else st}")'
    return
  fi
  local i st
  _los_status() {
    curl -sf -m 5 "$url/v1/models" | python3 -c 'import sys,json
for m in json.load(sys.stdin).get("data",[]):
    if m["id"]==sys.argv[1]:
        s=m.get("status"); print(s.get("value") if isinstance(s,dict) else s)' "$1" 2>/dev/null
  }
  st=$(_los_status "$model")
  [[ -z "$st" ]] && { echo "los-load: no model '$model' on $url (los-load with no args lists them)" >&2; return 1; }
  [[ "$st" == "loaded" ]] && { echo "los-load: $model already loaded"; return 0; }
  # The router answers a load for an already-loading/loaded model with a non-2xx, so do
  # not treat the POST status as the verdict -- the poll below is.
  curl -s -m 30 -X POST "$url/models/load" -H 'content-type: application/json' \
    -d "{\"model\":\"$model\"}" >/dev/null
  for i in $(seq 1 120); do
    st=$(_los_status "$model")
    case "$st" in
      loaded) echo "los-load: $model loaded"; return 0 ;;
      failed|unloaded) [[ $i -gt 3 ]] && { echo "los-load: $model status '$st' -- see: journalctl --user -u llama-router-heavy.service -n 50" >&2; return 1; } ;;
    esac
    sleep 5
  done
  echo "los-load: timed out waiting for $model" >&2; return 1
}

# Unload every model on the light router (default :7070) without stopping it, so a heavy
# model has the GPU. Light models reload on demand afterwards -- the cost is the reload,
# paid once and on purpose, instead of an LRU eviction paid by whoever comes back first.
los-drain() {
  local url="${1:-http://127.0.0.1:7070}" ids
  ids=$(curl -sf -m 5 "$url/v1/models" | python3 -c 'import sys,json
for m in json.load(sys.stdin).get("data",[]):
    st=(m.get("status") or {}).get("value")
    if st in ("loaded","loading"): print(m["id"])' 2>/dev/null) || { echo "los-drain: $url unreachable" >&2; return 1; }
  [[ -z "$ids" ]] && { echo "los-drain: nothing loaded on $url"; return 0; }
  local id; for id in $ids; do
    printf 'unload %s ... ' "$id"
    curl -sf -m 30 -X POST "$url/models/unload" -H 'content-type: application/json' \
      -d "{\"model\":\"$id\"}" >/dev/null && echo ok || echo FAILED
  done
}

# The cheap tier on :7071, mirroring llama-router-cheap.service. This exists to keep
# high-frequency shell traffic (summarize/tab_autoname, see variants/shared/_ai_tools.sh)
# off the light router: eviction there is pure LRU on last_used with NO pinning -- the
# `pin` preset key is commented out in llama.cpp's common/arg.cpp -- and every proxied
# request refreshes the target's timestamp. A tab-title call every few seconds therefore
# keeps the small model freshest and makes the ~28 GiB qwen3.8 the eviction victim during
# any idle gap. Separate port, separate LLAMA_CACHE, one model resident.
los-cheap() { LOS_PORT="${LOS_PORT:-7071}" _los_router cheap 1 "$@"; }
