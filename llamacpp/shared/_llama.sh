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

# ---- resume: put back what was resident after a router restart ---------------------
# The router is the biggest memory holder on the box, so it is the cgroup systemd-oomd
# picks when the user slice is under pressure (three times on 2026-11-06, see
# archlinux/llama-router.service). Restart=on-failure brings it back in ~5 s and
# --no-models-autoload makes it come back EMPTY: every client gets 400 "model is not
# loaded" until a human runs los-load. That is the model "unloading itself after a while".
#
# So: record the intent (what YOU loaded), and replay it whenever the router comes up
# with nothing. This is NOT autoload -- only ids that were resident at snapshot time are
# loaded, never the whole models directory, and los-restore stays out of the way if
# anything is already resident (someone else got there first).
#
# Driven by two systemd --user units installed by archlinux/install.sh:
#   los-snapshot.timer          every minute, los-snapshot
#   llama-router-restore.service  Wants= from the router unit, so every router start
#                                 (boot, crash, oom-kill, restart) replays the snapshot
# Opt out of the replay without stopping the snapshot: LOS_RESTORE=0 (drop-in on the
# restore unit). Tune the memory headroom with LOS_RESTORE_HEADROOM_GIB.
#
#   los-snapshot   record the resident ids into the state file (quiet unless changed)
#   los-restore    replay them if the router is reachable and has nothing resident
_LOS_STATE="${LOS_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/llamacpp/resident}"

# Resident = loaded, loading, or sleeping. Reads the /v1/models body on stdin, and prints
# nothing for a router that is not there -- so a drained box and a dead one are not the
# same answer to the caller.
_los_resident_ids() {
  python3 -c 'import sys,json
for m in json.load(sys.stdin).get("data",[]):
    st=(m.get("status") or {}).get("value")
    if st in ("loaded","loading","sleeping"): print(m["id"])' 2>/dev/null
}

los-snapshot() {
  local url="${LOS_URL:-http://127.0.0.1:7070}" body ids tmp
  # A router that does not ANSWER is not a router that was drained: writing an empty
  # file through a kill or a restart window would erase the very thing to resume.
  body=$(curl -sf -m 5 "$url/v1/models" 2>/dev/null) || return 0
  ids=$(printf '%s' "$body" | _los_resident_ids) || return 0
  # A restore in progress means an empty (or half-filled) router is a TRANSIENT state --
  # recording it would erase the very set the restore is replaying, and leave nothing to
  # replay if the router dies again before it finishes.
  if [[ -z "$ids" ]] && command -v systemctl >/dev/null 2>&1 &&
     systemctl --user is-active --quiet llama-router-restore.service 2>/dev/null; then
    return 0
  fi
  [[ "$ids" == "$(cat "$_LOS_STATE" 2>/dev/null)" ]] && return 0
  mkdir -p "${_LOS_STATE%/*}" || return 1
  tmp="${_LOS_STATE}.tmp"
  if [[ -n "$ids" ]]; then printf '%s\n' "$ids" >"$tmp"; else : >"$tmp"; fi
  mv "$tmp" "$_LOS_STATE" && echo "los-snapshot: ${_LOS_STATE##*/} -> ${ids:-nothing}"
}

# Greedy in recorded order, gated on free amdgpu GTT: the size `los` measured while the
# model was resident, else the weights on disk (shards summed), plus a headroom kept for
# the desktop and zram -- the pressure of a model loaded beside a full desktop is exactly
# what killed the router in the first place. Stops at the first FAILED load rather than
# piling more onto a box that is out of memory.
los-restore() {
  local url="${LOS_URL:-http://127.0.0.1:7070}" body plan verb id note i rc=0
  [[ "${LOS_RESTORE:-1}" == 1 ]] || { echo "los-restore: disabled (LOS_RESTORE=0)"; return 0; }
  [[ -f "$_LOS_STATE" ]] || { echo "los-restore: no snapshot at $_LOS_STATE -- nothing to resume"; return 0; }
  # At login this unit races the router's own start; give it a minute.
  for i in $(seq 1 20); do
    body=$(curl -sf -m 5 "$url/v1/models" 2>/dev/null) && break
    sleep 3
  done
  [[ -n "$body" ]] || { echo "los-restore: $url never answered -- giving up" >&2; return 1; }
  if [[ -n "$(printf '%s' "$body" | _los_resident_ids)" ]]; then
    echo "los-restore: the router already has models resident -- leaving them alone"
    return 0
  fi
  # The planner reads the router itself: the program comes in on stdin here (python3 -),
  # so the model list cannot share that stdin, and an env var would put a multi-KB body
  # under execve's 128 KiB per-argument cap. One extra GET costs nothing.
  plan=$(LOS_URL="$url" LOS_STATE_FILE="$_LOS_STATE" \
    LOS_HEADROOM_GIB="${LOS_RESTORE_HEADROOM_GIB:-16}" python3 - <<'PY'
import glob, json, os, urllib.request

GIB = 2 ** 30
headroom = float(os.environ.get("LOS_HEADROOM_GIB", 16)) * GIB
with urllib.request.urlopen(os.environ["LOS_URL"] + "/v1/models", timeout=5) as r:
    data = json.load(r).get("data", [])
models = {m["id"]: m for m in data if isinstance(m, dict) and isinstance(m.get("id"), str)}

def free_gtt():
    # The GTT window is what the models actually pin; None where there is no amdgpu
    # (macOS), which makes the gate a no-op instead of a guess.
    for total in sorted(glob.glob("/sys/class/drm/card*/device/mem_info_gtt_total")):
        try:
            t, u = int(open(total).read()), int(open(total.replace("_total", "_used")).read())
        except Exception:
            continue
        if t > 0:
            return t - u
    return None

def weights(model):
    args = (model.get("status") or {}).get("args") or []
    if "--model" not in args:
        return 0
    try:
        path = args[args.index("--model") + 1]
    except IndexError:
        return 0
    if not path or not os.path.exists(path):
        return 0
    name = os.path.basename(path)
    if "-of-" not in name:
        return os.path.getsize(path)
    stem = "-".join(name.split("-")[:-3])
    return sum(os.path.getsize(f) for f in
               glob.glob(os.path.join(os.path.dirname(path), stem + "-*of-*.gguf")))

def measured(mid):
    # id -> bytes pinned, written by the `los` menu while the model was resident: closer
    # than weights (KV + compute buffers included), absent for a model never shown there.
    path = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                        "los-menu", "resident.tsv")
    try:
        for line in open(path):
            key, _, value = line.partition("\t")
            if key == mid:
                return int(float(value))
    except Exception:
        pass
    return 0

try:
    want = [line.strip() for line in open(os.environ["LOS_STATE_FILE"]) if line.strip()]
except Exception:
    want = []

free = free_gtt()
for mid in want:
    model = models.get(mid)
    if model is None:
        print("SKIP\t%s\tis not served by this router" % mid)
        continue
    need = max(measured(mid), weights(model))
    if free is not None and need + headroom > free:
        print("SKIP\t%s\tneeds ~%.1f GiB, %.1f GiB free with a %.0f GiB headroom"
              % (mid, need / GIB, free / GIB, headroom / GIB))
        continue
    if free is not None:
        free -= need
    print("LOAD\t%s\t%s" % (mid, "~%.1f GiB" % (need / GIB) if need else "size unknown"))
PY
)
  [[ -n "$plan" ]] || { echo "los-restore: nothing in the snapshot"; return 0; }
  while IFS=$'\t' read -r verb id note; do
    [[ -n "$verb" ]] || continue
    if [[ "$verb" == SKIP ]]; then
      echo "los-restore: skipping $id -- $note"
      continue
    fi
    echo "los-restore: reloading $id ($note)"
    los-load "$id" || { echo "los-restore: $id failed -- stopping, do not pile loads onto a full box" >&2; rc=1; break; }
  done <<< "$plan"
  return $rc
}

# ---- Kokoro TTS (bin/kokoro-serve behind kokoro-tts.service) -----------------------
# Not a router model, but it holds ~1 GiB of RAM while loaded, and RAM is the one budget
# on the unified-memory box -- so it is driven from the same verbs: the `los` menu shows
# it as a row, los-drain unloads it with everything else, and this talks to it directly.
# Unloading keeps the daemon up; the next `say` reloads the model (~8 s, once).
#   los-tts            status (loaded / busy / rss / idle)
#   los-tts load       make it resident now, so the next say is instant
#   los-tts unload     release the weights (refused while a sentence is being spoken)
#   los-tts speak TEXT speak through the daemon, bypassing bin/say's fallback
_los_tts_socket() { echo "${KOKORO_SOCKET:-${XDG_RUNTIME_DIR:-/tmp}/kokoro-tts.sock}"; }
# One JSON request in, one JSON line out. Prints nothing and returns 1 when the daemon is
# not there, so callers can tell "no daemon" from "daemon said no".
_los_tts_rpc() {  # $1=op
  local sock; sock="$(_los_tts_socket)"
  [[ -S "$sock" ]] || return 1
  KOKORO_SOCKET="$sock" python3 -c 'import json,os,socket,sys
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(60)
try: s.connect(os.environ["KOKORO_SOCKET"])
except OSError: sys.exit(1)
s.sendall((json.dumps({"op":sys.argv[1]})+"\n").encode()); s.shutdown(socket.SHUT_WR)
out=b""
while (c:=s.recv(4096)): out+=c
sys.stdout.write(out.decode())' "$1" 2>/dev/null
}
los-tts() {
  local op="${1:-status}" out
  case "$op" in
    status|load|unload)
      out="$(_los_tts_rpc "$op")" || { echo "los-tts: no daemon at $(_los_tts_socket) -- systemctl --user start kokoro-tts.service" >&2; return 1; }
      printf '%s\n' "$out" | python3 -c 'import json,sys
d=json.load(sys.stdin); op=sys.argv[1]
if not d.get("ok"): print("los-tts: %s refused: %s" % (op, d.get("error")), file=sys.stderr); sys.exit(1)
st="loaded" if d["loaded"] else "unloaded"
if d["busy"]: st="busy (%d speaking)" % d["busy"]
print("kokoro  %-9s rss %d MiB  idle %ds  loads %d  spoken %.0fs%s" % (st, d["rss_mb"], d["idle_s"], d["loads"], d["spoken_s"],
      "  (idle-unload %ds)" % d["idle_unload_s"] if d["idle_unload_s"] else ""))' "$op" ;;
    speak)
      shift; [[ $# -gt 0 ]] || { echo "los-tts speak TEXT" >&2; return 1; }
      KOKORO_SOCKET="$(_los_tts_socket)" "${DOT_DIR:-$HOME/dotfiles}/bin/say" "$@" ;;
    -h|--help|*)
      echo "los-tts [status|load|unload|speak TEXT]   the resident Kokoro TTS (kokoro-tts.service)"
      [[ "$op" == -h || "$op" == --help ]] ;;
  esac
}

# Unload every model on the router (default :7070) without stopping it, so a big model
# has the GPU. Nothing comes back on its own afterwards (no autoload): los-load what you
# want next. The Kokoro daemon's model goes too (los-tts unload): it is the same RAM.
los-drain() {
  local url="${1:-http://127.0.0.1:7070}" ids
  ids=$(curl -sf -m 5 "$url/v1/models" | python3 -c 'import sys,json
for m in json.load(sys.stdin).get("data",[]):
    st=(m.get("status") or {}).get("value")
    if st in ("loaded","loading","sleeping"): print(m["id"])' 2>/dev/null) || { echo "los-drain: $url unreachable" >&2; ids=; }
  [[ -z "$ids" ]] && echo "los-drain: nothing loaded on $url"
  local id; for id in $ids; do
    printf 'unload %s ... ' "$id"
    curl -sf -m 30 -X POST "$url/models/unload" -H 'content-type: application/json' \
      -d "{\"model\":\"$id\"}" >/dev/null && echo ok || echo FAILED
  done
  if _los_tts_rpc status >/dev/null 2>&1; then
    printf 'unload kokoro (tts) ... '
    _los_tts_rpc unload | python3 -c 'import json,sys; d=json.load(sys.stdin); print("ok" if d.get("ok") else "FAILED (%s)" % d.get("error")); sys.exit(0 if d.get("ok") else 1)' || true
  fi
}
