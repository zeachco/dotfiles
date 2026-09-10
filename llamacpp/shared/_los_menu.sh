# `los` -- one discoverable fzf menu over the llama.cpp routers.
#
# The los-* verbs in _llama.sh are still the scriptable interface (and this menu calls
# them). This exists because remembering which of los-load / los-drain / los-server-heavy
# does what is the actual friction: one entry point, everything hovering with a preview
# that explains itself.
#
# Everything shown comes from ONE `/v1/models` call per tier. The router reports
# `status.args` and `status.preset` for UNLOADED models too, so context size, slot count,
# KV layout and the .ini section are all previewable without loading anything -- hovering
# a 91 GiB model costs nothing. `meta` (n_ctx, byte size) appears only once a model is
# loaded, so weights fall back to the on-disk size of `--model`.
#
# Resident GTT is read from the child's fdinfo rather than RSS: amdgpu pins GPU memory
# outside any process's RSS, so `ps` shows ~42 MiB for a 91 GiB model. See
# ryzen-llm-setup.md "Incident: the OOM of 2026-09-09".

# tier:port:unit -- the three routers in llamacpp/archlinux. Override to add a box.
LOS_MENU_TIERS="${LOS_MENU_TIERS:-light:7070:llama-router.service cheap:7071:llama-router-cheap.service heavy:7072:llama-router-heavy.service}"

_los_menu_deps() {
  local missing=
  command -v fzf >/dev/null 2>&1 || missing="$missing fzf"
  command -v python3 >/dev/null 2>&1 || missing="$missing python3"
  [[ -z "$missing" ]] && return 0
  echo "los: missing required tool(s):$missing" >&2
  echo "     install with: pac_install${missing}" >&2
  return 1
}

# Builds the whole menu into $1: index.tsv (key + display), meta.tsv (key + what it is)
# and one NNN.txt preview per row. Doing it in a single pass means previews are plain
# file reads -- hovering never re-queries a router, so the menu stays instant even when
# a tier is busy generating.
_los_menu_snapshot() {
  python3 - "$@" <<'PY'
import json, os, sys, glob, urllib.request, urllib.parse

outdir, tierspec = sys.argv[1], sys.argv[2]

# Measured footprints, so an UNLOADED model can still be shown the number that decides
# whether it fits: weights-on-disk badly understates it (qwen3.8 is 15.7 GiB of weights
# and ~40 GiB resident once its KV pool is allocated). Recorded whenever a model is seen
# loaded; never estimated, since KV cost per token is arch-specific (MLA, hybrid
# attention and quantized KV all change it) and a wrong guess here is what OOMs the box.
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
                     "los-menu", "resident.tsv")
measured = {}
try:
    for line in open(CACHE):
        k, v = line.rstrip("\n").split("\t")
        measured[k] = int(v)
except (OSError, ValueError):
    pass
DIM, GRN, YEL, RED, BOLD, OFF = "\033[2m", "\033[32m", "\033[33m", "\033[31m", "\033[1m", "\033[0m"

def gib(b):
    return "%.1f GiB" % (b / (1 << 30)) if b else "?"

def get(url, timeout=4):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return json.load(r)
    except Exception:
        return None

def arg(args, flag):
    """Value of `flag` in the child's resolved argv, or None."""
    try:
        return args[args.index(flag) + 1]
    except (ValueError, IndexError):
        return None

def weights_on_disk(path):
    """Sharded models name siblings -00001-of-0000N.gguf; sum them, else just the file."""
    if not path or not os.path.exists(path):
        return 0
    if "-of-" in os.path.basename(path):
        stem = os.path.basename(path).rsplit("-", 3)[0]
        return sum(os.path.getsize(p) for p in glob.glob(os.path.join(os.path.dirname(path), stem + "-*-of-*.gguf")))
    return os.path.getsize(path)

def resident_gtt(model_id):
    """amdgpu pins GPU memory outside RSS. Find the child by --alias, read its fdinfo.
    Several fds report the same per-client total, so take the max, never the sum."""
    for cmd in glob.glob("/proc/[0-9]*/cmdline"):
        try:
            with open(cmd, "rb") as f:
                parts = f.read().split(b"\0")
        except OSError:
            continue
        if b"--alias" not in parts:
            continue
        try:
            if parts[parts.index(b"--alias") + 1].decode() != model_id:
                continue
        except (IndexError, UnicodeDecodeError):
            continue
        best = 0
        for fd in glob.glob(os.path.join(os.path.dirname(cmd), "fdinfo", "*")):
            try:
                with open(fd) as f:
                    for line in f:
                        if line.startswith("drm-resident-gtt:"):
                            best = max(best, int(line.split()[1]) * 1024)
            except (OSError, ValueError, IndexError):
                pass
        return best
    return 0

def slots(port, model_id):
    """None when unknown. Returns (total, busy, cached)."""
    # autoload=false is load-bearing, not decoration: a model can unload between the
    # /v1/models snapshot and this call, and without it asking for slots would RELOAD it --
    # a 91 GiB load triggered by merely opening a menu. Same guard framework-rgb polls with.
    data = get("http://127.0.0.1:%d/slots?model=%s&autoload=false"
               % (port, urllib.parse.quote(model_id)))
    if not isinstance(data, list):
        return None
    busy = sum(1 for s in data if s.get("is_processing"))
    cached = sum(1 for s in data if s.get("n_prompt_tokens"))
    return len(data), busy, cached


tiers = []
for spec in tierspec.split():
    name, port, unit = spec.split(":", 2)
    tiers.append((name, int(port), unit))

# ---- gather -----------------------------------------------------------------
rows, reachable = [], {}
for name, port, unit in tiers:
    data = get("http://127.0.0.1:%d/v1/models" % port, timeout=3)
    reachable[name] = data is not None
    if not data:
        continue
    for m in data.get("data", []):
        st = m.get("status") or {}
        state = st.get("value") if isinstance(st, dict) else str(st)
        rows.append({
            "tier": name, "port": port, "unit": unit, "id": m["id"], "state": state,
            "args": st.get("args") or [], "preset": st.get("preset") or "",
            "meta": m.get("meta") or {},
        })

for r in rows:
    r["slots"] = slots(r["port"], r["id"]) if r["state"] == "loaded" else None
    r["gtt"] = resident_gtt(r["id"]) if r["state"] == "loaded" else 0
    r["bytes"] = r["meta"].get("size") or weights_on_disk(arg(r["args"], "--model"))
    if r["gtt"]:
        measured[r["id"]] = r["gtt"]

try:
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE, "w") as f:
        for k, v in sorted(measured.items()):
            f.write("%s\t%d\n" % (k, v))
except OSError:
    pass

# ---- header -----------------------------------------------------------------
head, free_gtt = [], 0
for tot in glob.glob("/sys/class/drm/card*/device/mem_info_gtt_total"):
    try:
        total = int(open(tot).read())
        used = int(open(tot.replace("_total", "_used")).read())
        free = free_gtt = total - used
        col = GRN if free > 16 * (1 << 30) else (YEL if free > 8 * (1 << 30) else RED)
        head.append("GPU %s%s free%s of %s GTT" % (col, gib(free), OFF, gib(total)))
    except (OSError, ValueError):
        pass
    break
loaded = [r for r in rows if r["state"] == "loaded"]
if loaded:
    head.append("%d loaded (%s)" % (len(loaded), ", ".join(r["id"] for r in loaded)))
down = [n for n, ok in reachable.items() if not ok]
if down:
    head.append("%sunreachable: %s%s" % (RED, " ".join(down), OFF))
open(os.path.join(outdir, "header.txt"), "w").write("  ·  ".join(head) or "no routers reachable")

# ---- rows -------------------------------------------------------------------
index, meta, n = [], [], 0

def emit(display, kind, preview, tier="", port="", mid="", state=""):
    global n
    key = "%03d" % n
    n += 1
    open(os.path.join(outdir, key + ".txt"), "w").write(preview)
    index.append("%s\t%s" % (key, display))
    meta.append("\t".join([key, kind, tier, str(port), mid, state]))

idle_n = sum(1 for r in loaded if r["slots"] and r["slots"][1] == 0)
held = sum(r["gtt"] for r in loaded if r["slots"] and r["slots"][1] == 0)
emit("%sdrain idle%s        %sunload what nobody is generating on%s" % (BOLD, OFF, DIM, OFF),
     "drain-idle",
     "drain idle\n\n"
     "  Unloads every model that has NO slot currently generating, on every reachable\n"
     "  router, leaving the routers themselves up.\n\n"
     "  Right now: %d of %d loaded model(s) are idle, holding %s of GPU memory.\n\n"
     "  Caveat -- idle is not abandoned. An idle model still holds its slots' cached\n"
     "  conversations; unloading discards them, and the next message from that client\n"
     "  re-ingests the whole prompt. The per-model preview shows how many slots hold a\n"
     "  cached context, so check before draining a tier someone is parked on.\n\n"
     "  Caveat -- this is not a fence. --models-max autoload means the next request for\n"
     "  a model pulls it straight back. To keep a tier down for a heavy session, stop\n"
     "  its unit instead. See ryzen-llm-setup.md \"Incident: the OOM of 2026-09-09\".\n"
     % (idle_n, len(loaded), gib(held)))

emit("%sload%s              %spick from the models that are not resident%s" % (BOLD, OFF, DIM, OFF),
     "load",
     "load\n\n"
     "  Lists every UNLOADED model across all routers and loads what you pick, waiting\n"
     "  until each actually reports 'loaded' rather than trusting the POST.\n\n"
     "  Tab marks several; they load in the order shown. A failed load stops the batch --\n"
     "  the cause is almost always memory, so the rest would fail the same way.\n\n"
     "  The heavy tier runs --no-models-autoload, so this is the only way to bring a\n"
     "  heavy model up from a shell; light/cheap would also autoload on first request.\n\n"
     "  Nothing coordinates memory between the routers. Loading a 91 GiB model with the\n"
     "  light tier resident fails on the GPU -- drain first. Each model's preview shows\n"
     "  what it needs against what is free.\n")

emit("%sunload%s            %spick from the models that are resident%s" % (BOLD, OFF, DIM, OFF),
     "unload",
     "unload\n\n"
     "  Lists every LOADED model across all routers and unloads what you pick, keeping\n"
     "  the routers up. This is how GPU memory is given back. Tab marks several.\n\n"
     "  Unlike 'drain idle' this does not care whether the model is busy: unloading one\n"
     "  mid-generation kills that request. The preview marks which models are working.\n")

emit("%slogs%s              %sfollow a router's journal%s" % (BOLD, OFF, DIM, OFF),
     "logs",
     "logs\n\n"
     "  Pick a tier and follow its DAEMON's journal (journalctl --user -u <unit> -f) -- the\n"
     "  systemd --user unit that normally serves that tier.\n\n"
     "  A tier started by hand with los-server-<tier> is not a unit and has no journal; its\n"
     "  output goes to the terminal you ran it in.\n\n"
     "  Model load failures land here, not in the client: an oversized load shows up as\n"
     "  a Vulkan/GGML allocation error in the router's log while the client just sees a\n"
     "  400. Ctrl-C to stop following.\n")

emit("%s%s%s" % (DIM, "─" * 58, OFF), "sep", "(separator -- pick a model below, or an action above)")

wid = max([len(r["id"]) for r in rows] + [10])
for r in sorted(rows, key=lambda r: (r["state"] != "loaded", r["tier"], r["id"])):
    a = r["args"]
    ctx = arg(a, "--ctx-size") or r["meta"].get("n_ctx")
    par = arg(a, "--parallel") or "1"
    unified = "--kv-unified" in a
    ck, cv = arg(a, "--cache-type-k") or "f16", arg(a, "--cache-type-v") or "f16"
    ngl = arg(a, "--n-gpu-layers")
    mpath = arg(a, "--model") or ""

    if r["state"] == "loaded":
        badge = "%sloaded%s" % (GRN, OFF)
        size = "%s%s GTT%s" % (DIM, gib(r["gtt"]) if r["gtt"] else gib(r["bytes"]), OFF)
        if r["slots"] and r["slots"][1]:
            badge = "%sbusy%s" % (YEL, OFF)
    else:
        badge = "%sunloaded%s" % (DIM, OFF)
        size = "%s%s on disk%s" % (DIM, gib(r["bytes"]), OFF)
    display = "%-6s %-*s  %-18s %s" % (r["tier"], wid, r["id"], badge, size)

    p = ["%s%s%s" % (BOLD, r["id"], OFF), ""]
    p.append("  tier       %s  (:%d, %s)" % (r["tier"], r["port"], r["unit"]))
    p.append("  state      %s" % r["state"])
    p.append("  weights    %s%s" % (gib(r["bytes"]), "" if r["meta"].get("size") else "  (on disk)"))
    if r["gtt"]:
        p.append("  resident   %s pinned as GTT  (weights + KV)" % gib(r["gtt"]))
    elif r["id"] in measured:
        need = measured[r["id"]]
        if not free_gtt:
            verdict = ""
        elif need <= free_gtt:
            verdict = "  %sfits -- %s free%s" % (GRN, gib(free_gtt), OFF)
        else:
            verdict = "  %sdoes NOT fit -- only %s free, drain first%s" % (RED, gib(free_gtt), OFF)
        p.append("  needs      %s to load%s" % (gib(need), verdict))
        p.append("             %smeasured when last resident, not estimated%s" % (DIM, OFF))
    else:
        p.append("  needs      %sunmeasured -- weights + a KV pool sized by ctx/kv-cache below;%s" % (DIM, OFF))
        p.append("             %sload it once and this shows the real figure%s" % (DIM, OFF))
    if r["meta"].get("n_params"):
        p.append("  params     %.1fB  %s" % (r["meta"]["n_params"] / 1e9, r["meta"].get("ftype", "")))
    p.append("")
    p.append("  context    %s tokens over %s slot(s)" % (ctx, par))
    if unified:
        p.append("  kv pool    %sshared%s -- one pool, any single chat can use all %s" % (GRN, OFF, ctx))
    else:
        try:
            p.append("  kv pool    split -- %d tokens per slot, fixed" % (int(ctx) // int(par)))
        except (TypeError, ValueError):
            p.append("  kv pool    split -- ctx divided evenly per slot")
    p.append("  kv cache   %s / %s" % (ck, cv))
    if ngl:
        p.append("  offload    %s layers%s" % (ngl, " (full GPU)" if ngl == "999" else ""))
    if r["slots"]:
        tot, busy, cached = r["slots"]
        p.append("  slots      %d total, %d generating, %d holding a cached context" % (tot, busy, cached))
        if busy:
            p.append("             %sIN USE -- unloading kills the request in flight%s" % (YEL, OFF))
        elif cached:
            p.append("             %sidle, but %d cached chat(s) would be discarded%s" % (DIM, cached, OFF))
    if mpath:
        p.append("")
        p.append("  %s%s%s" % (DIM, mpath, OFF))
    if r["preset"].strip():
        p.append("")
        p.append("  %s---- %s.ini ----%s" % (DIM, r["tier"], OFF))
        for line in r["preset"].strip().splitlines():
            p.append("  %s%s%s" % (DIM, line, OFF))
    p.append("")
    p.append("  %s[enter] %s this model%s" % (BOLD, "unload" if r["state"] == "loaded" else "load", OFF))
    emit(display, "model", "\n".join(p), r["tier"], r["port"], r["id"], r["state"])

open(os.path.join(outdir, "index.tsv"), "w").write("\n".join(index) + "\n")
open(os.path.join(outdir, "meta.tsv"), "w").write("\n".join(meta) + "\n")
PY
}

_los_menu_meta() {  # $1=dir $2=key $3=field-number
  awk -F'\t' -v k="$2" -v f="$3" '$1 == k { print $f }' "$1/meta.tsv"
}

# One model in or out. Load reuses los-load's poll (the router answers a load for an
# already-loading model with a non-2xx, so the POST status is not the verdict).
_los_menu_load()   { LOS_HEAVY_URL="http://127.0.0.1:$1" los-load "$2"; }
_los_menu_unload() {
  printf 'unload %s ... ' "$2"
  curl -sf -m 30 -X POST "http://127.0.0.1:$1/models/unload" \
    -H 'content-type: application/json' -d "{\"model\":\"$2\"}" >/dev/null \
    && echo ok || { echo FAILED; return 1; }
}

# Apply one verb to a newline-separated list of row keys.
# Loads stop at the first failure: the usual cause is memory, and every later load in the
# batch would fail the same way -- better one clear error than five.
_los_menu_run_many() {
  local dir="$1" keys="$2" verb="$3" k port id
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    port=$(_los_menu_meta "$dir" "$k" 4)
    id=$(_los_menu_meta "$dir" "$k" 5)
    if [[ "$verb" == load ]]; then
      _los_menu_load "$port" "$id" || {
        echo "los: stopping here -- a failed load is usually memory, so the rest of the" >&2
        echo "     batch would fail too. Unload something and retry." >&2
        return 1
      }
    else
      _los_menu_unload "$port" "$id"
    fi
  done <<< "$keys"
  return 0
}

# Toggle several models from the main list in one go.
#
# UNLOADS RUN FIRST, always. Marking "unload GLM" and "load qwen3.8" together is a swap,
# and it only fits if the memory is freed before the load is attempted -- the routers do
# not coordinate a budget, so doing it in selection order is exactly the OOM in
# ryzen-llm-setup.md "Incident: the OOM of 2026-09-09".
_los_menu_toggle_many() {
  local dir="$1" keys="$2" k unloads= loads=
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    if [[ "$(_los_menu_meta "$dir" "$k" 2)" != model ]]; then
      echo "los: actions run one at a time -- select models only, or the action alone" >&2
      return 1
    fi
    if [[ "$(_los_menu_meta "$dir" "$k" 6)" == loaded ]]; then
      unloads="$unloads$k"$'\n'
    else
      loads="$loads$k"$'\n'
    fi
  done <<< "$keys"

  [[ -n "$unloads" ]] && { _los_menu_run_many "$dir" "$unloads" unload || return 1; }
  [[ -n "$loads" ]]   && { _los_menu_run_many "$dir" "$loads" load   || return 1; }
  return 0
}

# Unload only what has no slot generating, everywhere.
_los_menu_drain_idle() {
  local spec tier port unit any=
  for spec in $LOS_MENU_TIERS; do
    tier="${spec%%:*}"; port="${spec#*:}"; port="${port%%:*}"
    local ids id
    ids=$(curl -sf -m 5 "http://127.0.0.1:$port/v1/models" 2>/dev/null | python3 -c 'import sys,json
for m in json.load(sys.stdin).get("data",[]):
    if ((m.get("status") or {}).get("value")) == "loaded": print(m["id"])' 2>/dev/null) || continue
    for id in $ids; do
      local busy
      # autoload=false: never let a liveness probe reload a model. See _los_menu_snapshot.
      busy=$(curl -sf -m 5 "http://127.0.0.1:$port/slots?model=$id&autoload=false" 2>/dev/null | python3 -c 'import sys,json
try: print(sum(1 for s in json.load(sys.stdin) if s.get("is_processing")))
except Exception: print(-1)' 2>/dev/null)
      case "$busy" in
        0) any=1; printf '%s/' "$tier"; _los_menu_unload "$port" "$id" ;;
        -1|"") echo "skip $tier/$id (slot state unknown)" ;;
        *) echo "skip $tier/$id ($busy slot(s) generating)" ;;
      esac
    done
  done
  [[ -z "$any" ]] && echo "nothing idle to drain"
  return 0
}

_los_menu_logs() {
  local spec tier port unit pick
  pick=$(for spec in $LOS_MENU_TIERS; do
      tier="${spec%%:*}"; unit="${spec##*:}"; port="${spec#*:}"; port="${port%%:*}"
      printf '%s\t%-6s %s%s (:%s)%s\n' "$unit" "$tier" $'\033[2m' "$unit" "$port" $'\033[0m'
    done | fzf --ansi --delimiter='\t' --with-nth=2.. --height=~40% --reverse \
               --prompt='logs > ' --header='Ctrl-C stops following' | cut -f1) || return 0
  [[ -z "$pick" ]] && return 0
  journalctl --user -u "$pick" -n 100 -f
}

# The menu. Loops so load/unload/drain land you back where you started; Esc exits.
los() {
  case "${1:-}" in
    -h|--help)
      echo "los                            interactive menu over the llama.cpp routers"
      echo "los-load <model>               load a model and wait until it reports loaded"
      echo "los-drain [url]                unload everything on a router (default :7070)"
      echo "los-server-{light,cheap,heavy} run a router in the FOREGROUND (the daemons'"
      echo "                               journals are the menu's 'logs' action instead)"
      return 0 ;;
  esac
  _los_menu_deps || return 1

  local dir; dir=$(mktemp -d "${TMPDIR:-/tmp}/los-menu.XXXXXX") || return 1
  trap 'rm -rf "$dir"' RETURN 2>/dev/null

  while :; do
    rm -f "$dir"/*.txt "$dir"/*.tsv 2>/dev/null
    _los_menu_snapshot "$dir" "$LOS_MENU_TIERS" || { rm -rf "$dir"; return 1; }
    [[ -s "$dir/index.tsv" ]] || { echo "los: no routers reachable ($LOS_MENU_TIERS)" >&2; rm -rf "$dir"; return 1; }

    # -m so several models can be toggled in one pass. With nothing marked, fzf returns
    # the hovered row, so the single-selection path below is the normal case.
    local keys
    keys=$(fzf --ansi --multi --delimiter='\t' --with-nth=2.. \
              --height=100% --reverse --prompt='los > ' \
              --header="$(cat "$dir/header.txt")"$'\n'"tab marks · models can be marked together, actions are one at a time" \
              --preview "cat $dir/{1}.txt" --preview-window='right:58%:wrap' \
              < "$dir/index.tsv" | cut -f1) || break
    [[ -z "$keys" ]] && break

    # The separator is selectable; drop it rather than making it an error.
    keys=$(printf '%s\n' "$keys" | while IFS= read -r k; do
             [[ -z "$k" ]] && continue
             [[ "$(_los_menu_meta "$dir" "$k" 2)" == sep ]] || printf '%s\n' "$k"
           done)
    [[ -z "$keys" ]] && continue

    if [[ $(printf '%s\n' "$keys" | grep -c .) -gt 1 ]]; then
      _los_menu_toggle_many "$dir" "$keys"
      continue
    fi

    local key="$keys" kind port id
    kind=$(_los_menu_meta "$dir" "$key" 2)
    port=$(_los_menu_meta "$dir" "$key" 4)
    id=$(_los_menu_meta "$dir" "$key" 5)

    case "$kind" in
      sep) continue ;;
      drain-idle) _los_menu_drain_idle ;;
      load|unload)
        local want="$kind" sub list
        # Join meta.tsv (state) onto index.tsv (display) and keep the rows this verb can
        # act on: unloaded models for `load`, loaded ones for `unload`.
        list=$(awk -F'\t' -v w="$want" '
                 NR == FNR { if ($2 == "model") state[$1] = $6; next }
                 ($1 in state) && ((state[$1] == "loaded") == (w == "unload"))
               ' "$dir/meta.tsv" "$dir/index.tsv")
        [[ -z "$list" ]] && { echo "los: nothing to $want"; continue; }
        sub=$(printf '%s\n' "$list" |
              fzf --ansi --multi --delimiter='\t' --with-nth=2.. --height=100% --reverse \
                  --prompt="$want > " --preview "cat $dir/{1}.txt" \
                  --header="tab marks several · they are ${want}ed in the order shown" \
                  --preview-window='right:58%:wrap' | cut -f1) || continue
        [[ -z "$sub" ]] && continue
        _los_menu_run_many "$dir" "$sub" "$want"
        ;;
      logs) _los_menu_logs ;;
      model)
        if [[ "$(_los_menu_meta "$dir" "$key" 6)" == loaded ]]; then
          _los_menu_unload "$port" "$id"
        else
          _los_menu_load "$port" "$id"
        fi ;;
    esac
  done
  rm -rf "$dir"
  return 0
}
