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

# ---- per-OS layout -----------------------------------------------------------------
# One router per box, on both OSes since 2026-11-06. The Strix Halo box serves
# ~/models/llama with llamacpp/archlinux/models.ini, loads nothing on its own
# (--no-models-autoload: every load is `los` / los-load), and keeps up to 8 models
# resident -- memory is the only budget. Until then Linux ran three routers (light
# :7070 / cheap :7071 / heavy :7072) to fence the autoloading light tier's LRU
# eviction; with autoload off there was nothing left to fence.
#
# The Mac has ONE 37.4 GiB Metal working set, a FLAT ~/models, and one preset file
# (llamacpp/osx/osx.ini, which the launchd plist also points at) whose three models
# already measure 33.06 GiB together.
_los_is_mac() { [[ "$(uname -s)" == "Darwin" ]]; }

if _los_is_mac; then
  LOS_CONF_DIR="${LOS_CONF_DIR:-$HOME/dotfiles/llamacpp/osx}"
else
  LOS_CONF_DIR="${LOS_CONF_DIR:-$HOME/dotfiles/llamacpp/archlinux}"
fi

# nproc is GNU coreutils and does NOT exist on macOS: `$(( $(nproc) / 2 ))` is a math
# error there, not a fallback. /usr/sbin is absent from PATH inside a devbox shell (and
# those are auto-entered on cd), so sysctl gets its absolute path first.
_los_ncpu() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
  elif [[ -x /usr/sbin/sysctl ]]; then
    /usr/sbin/sysctl -n hw.ncpu
  else
    sysctl -n hw.ncpu 2>/dev/null || echo 2
  fi
}

# Router mode: no -m, so llama-server loads nothing itself and forks one child
# process per model, routed on the JSON body's "model" field.
#
# The daemon is a systemd --user unit (llamacpp/archlinux/llama-router.service) or a
# launchd agent (llamacpp/osx). This manual launcher is for an ad-hoc FOREGROUND run
# outside the unit, e.g. on a different LOS_PORT or with a different build.
_los_router() {
  local max="$1"; shift
  local ini models_dir cache ncpu half_cores

  if _los_is_mac; then
    ini="$LOS_CONF_DIR/osx.ini"
    models_dir="$HOME/models"
  else
    ini="$LOS_CONF_DIR/models.ini"
    models_dir="$HOME/models/llama"
  fi
  # The SAME cache as the daemon, on purpose: pinning LLAMA_CACHE is what makes
  # GET /v1/models return exactly the directories under the models dir, so a foreground
  # run with its own cache would enumerate a different model set than the daemon does.
  cache="$HOME/.cache/llama.cpp-router"

  # Fail on the missing piece by name. llama-server starts happily with a models dir
  # that is not there and a preset it cannot read, then serves an empty model list --
  # a router that answers /health and has nothing to route.
  [[ -f "$ini" ]] || { echo "_los_router: no preset file at $ini" >&2; return 1; }
  [[ -d "$models_dir" ]] || { echo "_los_router: no models directory at $models_dir" >&2; return 1; }

  ncpu="$(_los_ncpu)"
  [[ -n "$ncpu" ]] || ncpu=2
  half_cores=$(( ncpu / 2 ))
  ((half_cores < 1)) && half_cores=1
  ensure_llama_cpp || return 1
  LLAMA_CACHE="$cache" \
    "$LLAMA_CPP_BUILD/bin/llama-server" \
      --models-dir "$models_dir" \
      --models-preset "$ini" \
      --models-max "$max" \
      --host 127.0.0.1 --port "${LOS_PORT:-7070}" \
      -to 3600 \
      --threads "${LOS_THREADS:-$half_cores}" \
      --threads-batch "${LOS_THREADS:-$half_cores}" \
      "$@"
}

# Run the router in the FOREGROUND, mirroring the daemon's shape on this host:
# --no-models-autoload and --models-max 8 on Linux (llama-router.service), 4 with
# autoload on the Mac (the launchd plist). The daemon owns :7070, so stop it first
# (`systemctl --user stop llama-router.service`, or on the Mac
# `launchctl bootout gui/$(id -u)/com.zeachco.llama-router`) or pass a free LOS_PORT.
#
# The los-server prefix is the point of the name: this STARTS A SERVER, which is a
# different kind of thing from the verbs below (los-load / los-drain, which talk to a
# router already running) and from the `los` menu (llamacpp/shared/_los_menu.sh).
# Daemon logs are the menu's `logs` action, not here.
los-server() {
  if _los_is_mac; then
    _los_router 4 "$@"
  else
    _los_router 8 --no-models-autoload "$@"
  fi
}
# The pre-2026-11-06 name, kept for muscle memory and the Mac profile's comments.
los-server-light() { los-server "$@"; }

# Load a model explicitly. The router runs --no-models-autoload, so a request for an
# unloaded model is refused with 400 "model is not loaded" instead of pulling ~90 GiB
# under someone's feet -- this (or the `los` menu, or pi's model picker through
# llamacpp-discover.ts) is how anything becomes resident. Nothing checks memory for
# you here: `los` shows the measured footprint against free GTT; drain first if it
# does not fit.
#   los-load                      # list what the router has and what is loaded
#   los-load gpt-oss-120b-MXFP4   # load it, wait until ready
los-load() {
  local url="${LOS_URL:-http://127.0.0.1:7070}" model="${1:-}"
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
  # sleep-idle-seconds (the .ini presets): the child is up but has released its
  # weights; the router refuses a load ("not ready") and the first real request
  # wakes it. Nothing to do here.
  [[ "$st" == "sleeping" ]] && { echo "los-load: $model is resident but asleep -- the first request wakes it"; return 0; }
  # The router answers a load for an already-loading/loaded model with a non-2xx, so do
  # not treat the POST status as the verdict -- the poll below is.
  curl -s -m 30 -X POST "$url/models/load" -H 'content-type: application/json' \
    -d "{\"model\":\"$model\"}" >/dev/null
  for i in $(seq 1 120); do
    st=$(_los_status "$model")
    case "$st" in
      loaded) echo "los-load: $model loaded"; return 0 ;;
      sleeping) echo "los-load: $model is resident but asleep -- the first request wakes it"; return 0 ;;
      failed|unloaded) [[ $i -gt 3 ]] && { echo "los-load: $model status '$st' -- see: journalctl --user -u llama-router.service -n 50" >&2; return 1; } ;;
    esac
    sleep 5
  done
  echo "los-load: timed out waiting for $model" >&2; return 1
}

# Unload every model on the router (default :7070) without stopping it, so a big model
# has the GPU. Nothing comes back on its own afterwards (no autoload): los-load what you
# want next.
los-drain() {
  local url="${1:-http://127.0.0.1:7070}" ids
  ids=$(curl -sf -m 5 "$url/v1/models" | python3 -c 'import sys,json
for m in json.load(sys.stdin).get("data",[]):
    st=(m.get("status") or {}).get("value")
    if st in ("loaded","loading","sleeping"): print(m["id"])' 2>/dev/null) || { echo "los-drain: $url unreachable" >&2; return 1; }
  [[ -z "$ids" ]] && { echo "los-drain: nothing loaded on $url"; return 0; }
  local id; for id in $ids; do
    printf 'unload %s ... ' "$id"
    curl -sf -m 30 -X POST "$url/models/unload" -H 'content-type: application/json' \
      -d "{\"model\":\"$id\"}" >/dev/null && echo ok || echo FAILED
  done
}
