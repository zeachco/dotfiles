# `los` -- one discoverable fzf menu over the llama.cpp router.
#
# The los-* verbs in _llama.sh are still the scriptable interface (and this menu calls
# them). This exists because remembering which of los-load / los-drain / los-server
# does what is the actual friction: one entry point, everything hovering with a preview
# that explains itself. Since the router loads nothing on its own (--no-models-autoload,
# 2026-11-06), this menu IS how models become resident.
#
# Everything shown comes from ONE `/v1/models` call per router. The router reports
# `status.args` and `status.preset` for UNLOADED models too, so context size, slot count,
# KV layout and the .ini section are all previewable without loading anything -- hovering
# a 91 GiB model costs nothing. `meta` (n_ctx, byte size) appears only once a model is
# loaded, so weights fall back to the on-disk size of `--model`.
#
# Resident GTT is read from the child's fdinfo rather than RSS: amdgpu pins GPU memory
# outside any process's RSS, so `ps` shows ~42 MiB for a 91 GiB model. See
# docs/ryzen-llm-setup.md "Incident: the OOM of 2026-09-09".

# name:port:unit -- one router since 2026-11-06 (the light/cheap/heavy triple is gone).
# Still a list so a second router (another box, a foreground run on another LOS_PORT)
# can be added without touching the code: every loop below walks it.
LOS_MENU_TIERS="${LOS_MENU_TIERS:-router:7070:llama-router.service}"

# How many models a marked batch may load at once. Each model is its own child process,
# so the router parallelizes loads whether we do or not -- serializing them in the menu
# only added waiting. `export LOS_LOAD_PARALLEL=1` restores the old one-at-a-time batch.
# Raise it only if you want several multi-tens-of-GiB pulls racing each other for RAM and
# disk: nothing here (or in the router) meters memory.
LOS_LOAD_PARALLEL="${LOS_LOAD_PARALLEL:-4}"

# The Herdr reporter started beside the menu when `los` runs in a Herdr pane (see los()).
LOS_STATUS_BIN="${LOS_STATUS_BIN:-${DOT_DIR:-$HOME/dotfiles}/configs/herdr/plugins/los-status/los-status}"

# Loops over LOS_MENU_TIERS go through $(printf ...): zsh does not word-split an unquoted
# $var (shwordsplit is off), but it does split command substitution, and bash does both.
# Is this router's daemon installed on this box at all? A missing unit is information,
# not a failure: the menu lists it as "not installed" and restart skips it instead of
# erroring on it.
# launchd target for a systemd unit name: llama-router.service -> gui/501/com.zeachco.llama-router
_los_launchd_target() { echo "gui/$(id -u)/com.zeachco.${1%.service}"; }

_los_unit_installed() {
  local unit="$1"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    launchctl print "$(_los_launchd_target "$unit")" >/dev/null 2>&1
  else
    systemctl --user cat "$unit" >/dev/null 2>&1
  fi
}

# Space-separated tier names whose unit is missing, for the snapshot header.
_los_tiers_not_installed() {
  local spec tier unit out=
  for spec in $(printf "%s\n" $LOS_MENU_TIERS); do
    tier="${spec%%:*}"; unit="${spec##*:}"
    _los_unit_installed "$unit" || out="$out $tier"
  done
  echo "${out# }"
}

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
  LOS_NOT_INSTALLED="$(_los_tiers_not_installed)" LOS_LOAD_PARALLEL="$LOS_LOAD_PARALLEL" python3 - "$@" <<'PY'
import json, os, sys, glob, urllib.request, urllib.parse

outdir, tierspec = sys.argv[1], sys.argv[2]
not_installed = set(os.environ.get("LOS_NOT_INSTALLED", "").split())
# Batch width, so this text cannot drift from what _los_menu_run_many actually does.
load_parallel = os.environ.get("LOS_LOAD_PARALLEL") or "4"

# Measured footprints, so an UNLOADED model can still be shown the number that decides
# whether it fits: weights-on-disk badly understates it (qwen3.8 is 15.3 GiB of weights
# and 32.5 GiB resident once its KV pool is allocated -- models.ini, measured). Recorded whenever a model is seen
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


# The Kokoro TTS daemon (bin/kokoro-serve): not a router, but ~1 GiB of the same RAM
# while loaded, so it gets a row and is part of drain. None = no daemon on this box.
TTS_SOCK = os.environ.get("KOKORO_SOCKET") or os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "kokoro-tts.sock")
def tts_status():
    import socket
    if not os.path.exists(TTS_SOCK):
        return None
    try:
        c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); c.settimeout(3)
        c.connect(TTS_SOCK); c.sendall(b'{"op":"status"}\n'); c.shutdown(socket.SHUT_WR)
        out = b""
        while (chunk := c.recv(4096)):
            out += chunk
        return json.loads(out)
    except (OSError, ValueError):
        return None
tts = tts_status()

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

# A "sleeping" child (sleep-idle-seconds in the .ini) has released its weights and
# KV; /slots is NOT in the set of endpoints that bypass sleep, so probing it would
# RELOAD the model. Only ever probe what reports "loaded".
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
asleep = [r for r in rows if r["state"] == "sleeping"]
if loaded:
    head.append("%d loaded (%s)" % (len(loaded), ", ".join(r["id"] for r in loaded)))
if asleep:
    head.append("%d asleep (%s)" % (len(asleep), ", ".join(r["id"] for r in asleep)))
if tts and tts.get("loaded"):
    head.append("tts %s MiB" % tts["rss_mb"])
down = [n for n, ok in reachable.items() if not ok and n not in not_installed]
if down:
    head.append("%sunreachable: %s%s" % (RED, " ".join(down), OFF))
absent = [n for n, _, _ in tiers if n in not_installed]
if absent:
    head.append("%snot installed: %s%s" % (DIM, " ".join(absent), OFF))
open(os.path.join(outdir, "header.txt"), "w").write("  ·  ".join(head) or "no router reachable")

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
     "  Unloads every model that has NO slot currently generating, leaving the router\n"
     "  itself up.\n\n"
     "  Right now: %d of %d loaded model(s) are idle, holding %s of GPU memory.\n\n"
     "  Caveat -- idle is not abandoned. An idle model still holds its slots' cached\n"
     "  conversations; unloading discards them, and the next message from that client\n"
     "  re-ingests the whole prompt. The per-model preview shows how many slots hold a\n"
     "  cached context, so check before draining a model someone is parked on.\n\n"
     "  Nothing comes back on its own: the router runs --no-models-autoload, so what\n"
     "  you drain stays down until 'load'.\n\n"
     "  The Kokoro TTS model (the 'kokoro' row) is drained too when it is not speaking;\n"
     "  unlike the router models it DOES come back on its own, on the next `say`.\n"
     % (idle_n, len(loaded), gib(held)))

emit("%sload%s              %spick from the models that are not resident%s" % (BOLD, OFF, DIM, OFF),
     "load",
     "load\n\n"
     "  Lists every UNLOADED model and loads what you pick, waiting until each actually\n"
     "  reports 'loaded' rather than trusting the POST.\n\n"
     "  Tab marks several: up to %s load at a time (LOS_LOAD_PARALLEL), and a failed load\n"
     "  stops the batch -- the cause is almost always memory, so the rest would fail the\n"
     "  same way.\n\n"
     "  The router runs --no-models-autoload, so this (los-load in a shell, or picking\n"
     "  the model in pi) is the only way anything becomes resident.\n\n"
     "  Nothing refuses a load that does not fit: loading a 91 GiB model with the daily\n"
     "  set resident fails on the GPU, or worse, OOMs the box -- drain first. Each\n"
     "  model's preview shows what it needs against what is free.\n"
     % (load_parallel,))

emit("%sunload%s            %spick from the models that are resident%s" % (BOLD, OFF, DIM, OFF),
     "unload",
     "unload\n\n"
     "  Lists every LOADED model and unloads what you pick, keeping the router up.\n"
     "  This is how GPU memory is given back. Tab marks several.\n\n"
     "  Unlike 'drain idle' this does not care whether the model is busy: unloading one\n"
     "  mid-generation kills that request. The preview marks which models are working.\n")

emit("%slogs%s              %sfollow the router's journal%s" % (BOLD, OFF, DIM, OFF),
     "logs",
     "logs\n\n"
     "  Follow the DAEMON's journal (journalctl --user -u <unit> -f) -- the systemd\n"
     "  --user unit that normally serves the router.\n\n"
     "  A router started by hand with los-server is not a unit and has no journal; its\n"
     "  output goes to the terminal you ran it in.\n\n"
     "  Model load failures land here, not in the client: an oversized load shows up as\n"
     "  a Vulkan/GGML allocation error in the router's log while the client just sees a\n"
     "  400. Ctrl-C to stop following.\n")

emit("%srestart%s           %srestart the router daemon%s" % (BOLD, OFF, DIM, OFF),
     "restart",
     "restart\n\n"
     "  Restarts the DAEMON (systemctl --user restart <unit>; launchctl kickstart -k on\n"
     "  macOS), reachable or not -- this is the way to bring back a router the header\n"
     "  lists as unreachable, or to pick up an edited .ini. A router whose unit is not\n"
     "  installed on this box (the header's 'not installed') is skipped.\n\n"
     "  Every model is unloaded by this: in-flight requests die and all cached contexts\n"
     "  are gone. Nothing comes back on its own (--no-models-autoload): use 'load'.\n\n"
     "  Same thing as `los-restart-all` in a shell, which also works when the menu\n"
     "  cannot open because no router answers.\n")

emit("%ssync-models%s       %spush model catalogs into pi and opencode%s" % (BOLD, OFF, DIM, OFF),
     "sync-models",
     "sync-models\n\n"
     "  Rewrites the llamacpp* and openrouter model lists for both clients from their\n"
     "  live OpenAI-compatible /v1/models endpoints:\n\n"
     "    pi        configs/pi/.pi/agent/models.json\n"
     "    opencode  configs/opencode/.config/opencode/opencode.json\n\n"
     "  The live paths are stowed symlinks, and the sync writes through to the real files,\n"
     "  so changes are git-tracked -- `gd` after. Other providers are never touched.\n\n"
     "  OpenRouter's catalog is filtered to text-output chat models; its public model list\n"
     "  does not require a key. Requests use OPENROUTER_API_KEY (or Pi's /login auth).\n\n"
     "  Refreshed: membership and endpoint metadata such as context, image input, reasoning,\n"
     "  tool support, output limits, and pricing. Hand-tuning is preserved.\n\n"
     "  Loads nothing: /v1/models reports unloaded local models too, so a fully idle box\n"
     "  still syncs the complete set. pi reloads models.json on the next /model open;\n"
     "  restart opencode after syncing.\n\n"
     "  Same thing as `llamacpp-sync` in a shell, and what dotfiles_update runs.\n")

emit("%s%s%s" % (DIM, "─" * 58, OFF), "sep", "(separator -- pick a model below, or an action above)")

wid = max([len(r["id"]) for r in rows] + [10])
for r in sorted(rows, key=lambda r: ({"loaded": 0, "sleeping": 1}.get(r["state"], 2), r["tier"], r["id"])):
    a = r["args"]
    ctx = arg(a, "--ctx-size") or r["meta"].get("n_ctx")
    par = arg(a, "--parallel") or "1"
    unified = "--kv-unified" in a
    cap = arg(a, "--kv-unified-per-slot")
    ck, cv = arg(a, "--cache-type-k") or "f16", arg(a, "--cache-type-v") or "f16"
    ngl = arg(a, "--n-gpu-layers")
    mpath = arg(a, "--model") or ""

    if r["state"] == "loaded":
        badge = "%sloaded%s" % (GRN, OFF)
        size = "%s%s GTT%s" % (DIM, gib(r["gtt"]) if r["gtt"] else gib(r["bytes"]), OFF)
        if r["slots"] and r["slots"][1]:
            badge = "%sbusy%s" % (YEL, OFF)
    elif r["state"] == "sleeping":
        badge = "%sasleep%s" % (DIM, OFF)
        size = "%sno GTT, wakes on request%s" % (DIM, OFF)
    else:
        badge = "%sunloaded%s" % (DIM, OFF)
        size = "%s%s on disk%s" % (DIM, gib(r["bytes"]), OFF)
    # Prefix: busy/total slots for a loaded model (green idle, yellow partial, red maxed),
    # the tier name dimmed for everything else. Padding ignores the escape codes.
    if r["state"] == "loaded" and r["slots"]:
        tot, busy = r["slots"][0], r["slots"][1]
        col = GRN if busy == 0 else RED if busy >= tot else YEL
        prefix = "%s%-6s%s" % (col, "%d/%d" % (busy, tot), OFF)
    else:
        prefix = "%s%-6s%s" % (DIM, r["tier"], OFF)
    display = "%s %-*s  %-18s %s" % (prefix, wid, r["id"], badge, size)

    p = ["%s%s%s" % (BOLD, r["id"], OFF), ""]
    p.append("  router     %s  (:%d, %s)" % (r["tier"], r["port"], r["unit"]))
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
    if unified and cap:
        p.append("  kv pool    %sshared%s -- one pool of %s, any single chat capped at %s" % (GRN, OFF, ctx, cap))
    elif unified:
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
        p.append("  %s---- preset section ----%s" % (DIM, OFF))
        for line in r["preset"].strip().splitlines():
            p.append("  %s%s%s" % (DIM, line, OFF))
    if r["state"] == "sleeping":
        p.append("")
        p.append("  %sasleep (sleep-idle-seconds): weights and KV released, the child is still up.%s" % (DIM, OFF))
        p.append("  %sThe first request reloads it (and re-ingests its chats). Enter stops the child.%s" % (DIM, OFF))
    p.append("")
    p.append("  %s[enter] %s this model%s" % (BOLD, "unload" if r["state"] in ("loaded", "sleeping") else "load", OFF))
    emit(display, "model", "\n".join(p), r["tier"], r["port"], r["id"], r["state"])

# ---- the TTS daemon, after the models ---------------------------------------------
if tts is not None:
    if tts.get("busy"):
        badge, size = "%sbusy%s" % (YEL, OFF), "%s%d MiB RSS%s" % (DIM, tts["rss_mb"], OFF)
    elif tts.get("loaded"):
        badge, size = "%sloaded%s" % (GRN, OFF), "%s%d MiB RSS%s" % (DIM, tts["rss_mb"], OFF)
    else:
        badge, size = "%sunloaded%s" % (DIM, OFF), "%s%d MiB RSS, ~1 GiB loaded%s" % (DIM, tts["rss_mb"], OFF)
    state = "loaded" if tts.get("loaded") else "unloaded"
    display = "%s%-6s%s %-*s  %-18s %s" % (DIM, "tts", OFF, wid, "kokoro", badge, size)
    p = ["%skokoro%s  (Kokoro-82M text-to-speech, bin/kokoro-serve)" % (BOLD, OFF), ""]
    p.append("  unit       kokoro-tts.service  (socket %s)" % TTS_SOCK)
    p.append("  state      %s%s" % (state, "  -- %d sentence(s) being spoken" % tts["busy"] if tts.get("busy") else ""))
    p.append("  resident   %d MiB RSS  (system RAM, not GTT: CPU torch)" % tts["rss_mb"])
    if tts.get("load_s"):
        p.append("  last load  %.1fs" % tts["load_s"])
    p.append("  idle       %ds%s" % (tts["idle_s"], "  (unloads itself after %ds)" % tts["idle_unload_s"] if tts.get("idle_unload_s") else "  (never unloads on its own)"))
    p.append("  spoken     %.0fs of audio over %d load(s) since the daemon started (%dh%02dm ago)"
             % (tts["spoken_s"], tts["loads"], tts["uptime_s"] // 3600, tts["uptime_s"] % 3600 // 60))
    p.append("")
    p.append("  %sWhy it is here: `say` keeps this process resident so a sentence costs ~0.2 s%s" % (DIM, OFF))
    p.append("  %sinstead of a 7-9 s model load. Unloading frees ~700 MiB and keeps the daemon up;%s" % (DIM, OFF))
    p.append("  %sthe next `say` reloads it (once, ~8 s). Same thing as `los-tts load|unload`.%s" % (DIM, OFF))
    if tts.get("busy"):
        p.append("")
        p.append("  %sIN USE -- unload is refused until the sentence ends%s" % (YEL, OFF))
    p.append("")
    p.append("  %s[enter] %s the TTS model%s" % (BOLD, "unload" if state == "loaded" else "load", OFF))
    emit(display, "tts", "\n".join(p), "tts", "", "kokoro", state)

open(os.path.join(outdir, "index.tsv"), "w").write("\n".join(index) + "\n")
open(os.path.join(outdir, "meta.tsv"), "w").write("\n".join(meta) + "\n")
PY
}

_los_menu_meta() {  # $1=dir $2=key $3=field-number
  awk -F'\t' -v k="$2" -v f="$3" '$1 == k { print $f }' "$1/meta.tsv"
}

# One model in or out. Load reuses los-load's poll (the router answers a load for an
# already-loading model with a non-2xx, so the POST status is not the verdict).
_los_menu_load()   { LOS_URL="http://127.0.0.1:$1" los-load "$2"; }
_los_menu_unload() {
  printf 'unload %s ... ' "$2"
  curl -sf -m 30 -X POST "http://127.0.0.1:$1/models/unload" \
    -H 'content-type: application/json' -d "{\"model\":\"$2\"}" >/dev/null \
    && echo ok || { echo FAILED; return 1; }
}

# One model in or out, as a background job. Output goes to per-tag files at the caller's
# redirection and the exit status to $dir/rc.<tag>, because a background job's status is
# awkward to collect in order and `wait`'s exit code covers only the last pid.
_los_menu_job() {  # $1=dir $2=tag $3=port $4=id $5=verb
  local dir="$1" tag="$2" port="$3" id="$4" verb="$5" rc
  if [[ "$verb" == load ]]; then
    LOS_URL="http://127.0.0.1:$port" los-load "$id"
  else
    _los_menu_unload "$port" "$id"
  fi
  rc=$?
  printf '%s\n' "$rc" > "$dir/rc.$tag"
}

# Wait for one round of jobs, then print what each said in selection order, whatever order
# they finished in. Returns 1 if any job in the round failed.
_los_menu_reap() {  # $1=dir $2=first-tag $3=last-tag $4..=pids
  local dir="$1" first="$2" last="$3" rc=0 i
  shift 3
  wait "$@" 2>/dev/null
  for (( i = first; i <= last; i++ )); do
    [[ -e "$dir/log.$i" ]] && cat "$dir/log.$i"
    [[ "$(cat "$dir/rc.$i" 2>/dev/null)" == "0" ]] || rc=1
    rm -f "$dir/log.$i" "$dir/rc.$i"
  done
  return $rc
}

# Apply one verb to a newline-separated list of row keys, LOS_LOAD_PARALLEL models at a
# time (default 4; 1 = the old serial batch).
#
# Why it was serial: los-load says nothing until the model reports "loaded", so marking
# the daily set meant the SUM of the load times -- minutes of idle cursor for work the
# router does concurrently anyway. Rounds of 4 make the batch cost the slowest model in
# each round instead.
#
# Rounds rather than a rolling pool: keeping a pool topped up means `wait -n` or reading
# `jobs -pr`, and neither behaves the same in bash and in zsh -- this file is sourced by
# both. A round loses at most one straggler's poll interval (los-load checks every 5 s).
#
# Fail-fast survives, one round later: after a round with a failure the batch stops. The
# cause is almost always memory, so every later round would fail the same way, and each
# failure would burn los-load's full 10-minute timeout before saying so.
#
# Memory ordering is NOT relaxed: _los_menu_toggle_many still runs the whole unload group
# before the first load round, which is what keeps a swap from becoming the OOM of
# 2026-09-09. What parallelizing DOES add is that up to 4 loads allocate at once, and
# nothing meters that -- the preview's "fits / does NOT fit" line is the only brake.
_los_menu_run_many() {
  local dir="$1" keys="$2" verb="$3" k port id
  local wide="$LOS_LOAD_PARALLEL" first=1 n=0 rc=0
  # An array, not a space-separated string: zsh does not word-split an unquoted $var, so
  # `wait $pids` there would pass one garbage pid and return at once -- every rc file read
  # before its job finished, and the batch "failing" instantly.
  local -a pids=()
  [[ "$wide" =~ ^[0-9]+$ ]] && (( wide >= 1 )) || wide=4

  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    port=$(_los_menu_meta "$dir" "$k" 4)
    id=$(_los_menu_meta "$dir" "$k" 5)
    n=$((n + 1))
    _los_menu_job "$dir" "$n" "$port" "$id" "$verb" > "$dir/log.$n" 2>&1 &
    pids+=("$!")
    if (( n - first + 1 >= wide )); then
      _los_menu_reap "$dir" "$first" "$n" "${pids[@]}" || rc=1
      pids=(); first=$((n + 1))
      if (( rc )); then
        if [[ "$verb" == load ]]; then
          echo "los: stopping here -- a failed load is usually memory, so the rest of the" >&2
          echo "     batch would fail too. Unload something and retry." >&2
        else
          echo "los: stopping here -- a model in this batch did not unload (see above)" >&2
        fi
        break
      fi
    fi
  done <<< "$keys"

  (( ${#pids[@]} > 0 )) && { _los_menu_reap "$dir" "$first" "$n" "${pids[@]}" || rc=1; }
  return $rc
}

# Toggle several models from the main list in one go.
#
# UNLOADS RUN FIRST, always. Marking "unload GLM" and "load qwen3.8" together is a swap,
# and it only fits if the memory is freed before the load is attempted -- the router
# refuses no load for memory, so doing it in selection order is exactly the OOM in
# docs/ryzen-llm-setup.md "Incident: the OOM of 2026-09-09".
_los_menu_toggle_many() {
  local dir="$1" keys="$2" k unloads= loads=
  local tts_verb=
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    if [[ "$(_los_menu_meta "$dir" "$k" 2)" == tts ]]; then
      [[ "$(_los_menu_meta "$dir" "$k" 6)" == loaded ]] && tts_verb=unload || tts_verb=load
      continue
    fi
    if [[ "$(_los_menu_meta "$dir" "$k" 2)" != model ]]; then
      echo "los: actions run one at a time -- select models only, or the action alone" >&2
      return 1
    fi
    # A sleeping child is resident (its process is up), so it belongs with the unloads.
    case "$(_los_menu_meta "$dir" "$k" 6)" in
      loaded|sleeping) unloads="$unloads$k"$'\n' ;;
      *)               loads="$loads$k"$'\n' ;;
    esac
  done <<< "$keys"

  [[ "$tts_verb" == unload ]] && { los-tts unload || return 1; }
  [[ -n "$unloads" ]] && { _los_menu_run_many "$dir" "$unloads" unload || return 1; }
  [[ -n "$loads" ]]   && { _los_menu_run_many "$dir" "$loads" load   || return 1; }
  [[ "$tts_verb" == load ]] && { los-tts load || return 1; }
  return 0
}

# Unload only what has no slot generating.
_los_menu_drain_idle() {
  local spec tier port unit any=
  for spec in $(printf "%s\n" $LOS_MENU_TIERS); do
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
  # The TTS daemon: its status says whether a sentence is in flight.
  local tts; tts="$(_los_tts_rpc status 2>/dev/null)" || tts=
  if [[ -n "$tts" ]]; then
    case "$(printf '%s' "$tts" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("busy" if d.get("busy") else "loaded" if d.get("loaded") else "unloaded")' 2>/dev/null)" in
      loaded) any=1; printf 'tts/'; los-tts unload >/dev/null && echo "unload kokoro ... ok" || echo "unload kokoro ... FAILED" ;;
      busy) echo "skip tts/kokoro (speaking)" ;;
    esac
  fi
  [[ -z "$any" ]] && echo "nothing idle to drain"
  return 0
}

# Point pi's llamacpp* providers at loopback when THIS box serves the models.
#
# ~/models present means the router is local. The configured host names the OTHER box
# (oli-llms.local), which from here resolves to a different machine or, as on the mac, to
# nothing -- so pi would sync from, and then talk to, a router that is not the one running.
#
# Pi has no hook that can reach the endpoint (before_provider_request carries only the
# payload), so the URL has to be in models.json, and this is what puts it there. opencode is
# left alone: its config is only stowed on the router box, where the name resolves to the box
# itself. OpenRouter is not localized.
_los_menu_localize_pi() {
  local models_json="${1:-$HOME/.pi/agent/models.json}"
  [[ -d "$HOME/models" ]] || return 0
  [[ -f "$models_json" ]] || return 0
  command -v jq >/dev/null 2>&1 || { echo "los: jq missing; left pi pointing at the remote host" >&2; return 0; }

  local real tmp mode
  # Follow the stow symlink: the file to edit is the one in ~/dotfiles, so the change is
  # git-tracked and reviewable like the model list itself.
  real=$(realpath "$models_json") || return 0
  tmp=$(mktemp "${real}.los.XXXXXX") || return 0

  if jq '.providers |= with_entries(
           if (.key | startswith("llamacpp")) and (.value.baseUrl? // "" | test("^https?://"))
           then .value.baseUrl |= sub("^(?<s>https?://)[^:/]+"; "\(.s)127.0.0.1")
           else . end)' "$real" >"$tmp" && [[ -s "$tmp" ]]; then
    # stat is not portable; try BSD then GNU, and just keep the default on neither.
    mode=$(stat -f '%Lp' "$real" 2>/dev/null || stat -c '%a' "$real" 2>/dev/null) && chmod "$mode" "$tmp"
    mv "$tmp" "$real"
  else
    rm -f "$tmp"
    echo "los: could not rewrite pi's baseUrl; left it pointing at the remote host" >&2
  fi
  return 0
}

# Rewrite pi's model definitions from the live router.
#
# The pause matters: the menu loop redraws fzf over the full terminal height the moment
# this returns, and the list of added/removed models -- the only output worth reading --
# would be painted over before it was read.
_los_menu_sync_models() {
  local sync="${DOT_DIR:-$HOME/dotfiles}/bin/llamacpp-sync"
  [[ -x "$sync" ]] || { echo "los: no llamacpp-sync at $sync" >&2; return 1; }
  _los_menu_localize_pi
  "$sync" "$@"
  local rc=$?
  printf '\n%s' "[enter] back to the menu "
  read -r
  return $rc
}

# Restart the router daemon(s), reachable or not. Public (not _los_menu_*) because it is
# the verb to reach for precisely when the menu refuses to open: `los` bails out when no
# router answers, and a crashed router is exactly that situation.
los-restart-all() {
  local spec tier unit rc=0
  for spec in $(printf "%s\n" $LOS_MENU_TIERS); do
    tier="${spec%%:*}"; unit="${spec##*:}"
    if ! _los_unit_installed "$unit"; then
      echo "skipped $tier ($unit not installed on this box)"
      continue
    fi
    if [[ "$(uname -s)" == "Darwin" ]]; then
      # kickstart -k restarts whether or not the job is running; stop+start does not.
      launchctl kickstart -k "$(_los_launchd_target "$unit")" && echo "restarted $tier ($unit)" || rc=1
    else
      systemctl --user restart "$unit" && echo "restarted $tier ($unit)" || rc=1
    fi
  done
  return $rc
}

_los_menu_restart_all() {
  los-restart-all
  printf '\n%s' "[enter] back to the menu "
  read -r
}

_los_menu_logs() {
  local spec tier port unit pick
  pick=$({ for spec in $(printf "%s\n" $LOS_MENU_TIERS); do
      tier="${spec%%:*}"; unit="${spec##*:}"; port="${spec#*:}"; port="${port%%:*}"
      printf '%s\t%-6s %s%s (:%s)%s\n' "$unit" "$tier" $'\033[2m' "$unit" "$port" $'\033[0m'
    done
    _los_unit_installed kokoro-tts.service && printf '%s\t%-6s %s%s%s\n' kokoro-tts.service tts $'\033[2m' kokoro-tts.service $'\033[0m'
    true; } | fzf --ansi --delimiter='\t' --with-nth=2.. --height=~40% --reverse \
               --prompt='logs > ' --header='Ctrl-C stops following' | cut -f1) || return 0
  [[ -z "$pick" ]] && return 0
  journalctl --user -u "$pick" -n 100 -f
}

# The menu. Loops so load/unload/drain land you back where you started; Esc exits.
los() {
  case "${1:-}" in
    -h|--help)
      echo "los                            interactive menu over the llama.cpp router"
      echo "los-load <model>               load a model and wait until it reports loaded"
      echo "los-drain [url]                unload everything on the router (default :7070) and the TTS model"
      echo "los-tts [status|load|unload]   the resident Kokoro TTS (kokoro-tts.service), ~1 GiB loaded"
      echo "los-restart-all                restart the router daemon (the menu's 'restart')"
      echo "LOS_LOAD_PARALLEL              models loaded at once by a marked batch in los (default 4)"
      echo "llamacpp-sync                  the menu's sync-models action, non-interactive"
      echo "los-server                     run the router in the FOREGROUND (the daemon's"
      echo "                               journal is the menu's 'logs' action instead)"
      return 0 ;;
  esac
  _los_menu_deps || return 1

  # Inside Herdr the menu gets its own tab: `los` here creates it and hands over, and the
  # copy running in that tab (LOS_TAB=1) is the one that draws the menu, with a reporter
  # beside it (configs/herdr/plugins/los-status) renaming the tab "los - busy/total
  # slots", feeding the sidebar's "resources" agent entry and refreshing the fzf header
  # every 2 s over fzf's --listen socket, which leaves marked rows alone.
  if [[ -n "${HERDR_PANE_ID:-}" && -z "${LOS_TAB:-}" ]]; then
    local pane
    pane=$(herdr tab create --label los --env LOS_TAB=1 --focus 2>/dev/null | grep -o '"pane_id":"[^"]*"' | head -1 | cut -d'"' -f4)
    [[ -n "$pane" ]] || { echo "los: herdr tab create failed" >&2; return 1; }
    herdr pane run "$pane" 'los; exit' >/dev/null
    return 0
  fi

  local dir; dir=$(mktemp -d "${TMPDIR:-/tmp}/los-menu.XXXXXX") || return 1
  local reporter= fzf_listen=()
  [[ -n "${ZSH_VERSION:-}" ]] && setopt localoptions nomonitor nonotify  # no "[1] pid" / "done" for the reporter
  if [[ -n "${HERDR_PANE_ID:-}" && -x "$LOS_STATUS_BIN" ]]; then
    local port; port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
    fzf_listen=(--listen "$port")
    LOS_FZF_PORT="$port" python3 "$LOS_STATUS_BIN" --report >/dev/null 2>&1 &
    reporter=$!
  fi
  trap 'rm -rf "$dir"; [[ -n "$reporter" ]] && kill "$reporter" 2>/dev/null' RETURN 2>/dev/null

  while :; do
    # find, not a glob: zsh aborts the whole command with "no matches found" when a
    # pattern matches nothing (the first pass, and any pass where a tier went away),
    # and that happens before the redirect can swallow it.
    find "$dir" -mindepth 1 -delete 2>/dev/null
    _los_menu_snapshot "$dir" "$LOS_MENU_TIERS" || { rm -rf "$dir"; return 1; }
    [[ -s "$dir/index.tsv" ]] || { echo "los: no router reachable ($LOS_MENU_TIERS) -- try los-restart-all" >&2; rm -rf "$dir"; return 1; }

    # -m so several models can be toggled in one pass. With nothing marked, fzf returns
    # the hovered row, so the single-selection path below is the normal case.
    local keys
    keys=$(fzf --ansi --multi --delimiter='\t' --with-nth=2.. "${fzf_listen[@]}" \
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
                 ($1 in state) && ((state[$1] == "loaded" || state[$1] == "sleeping") == (w == "unload"))
               ' "$dir/meta.tsv" "$dir/index.tsv")
        [[ -z "$list" ]] && { echo "los: nothing to $want"; continue; }
        sub=$(printf '%s\n' "$list" |
              fzf --ansi --multi --delimiter='\t' --with-nth=2.. --height=100% --reverse \
                  --prompt="$want > " --preview "cat $dir/{1}.txt" \
                  --header="tab marks several · up to ${LOS_LOAD_PARALLEL} at a time · one failure stops the batch" \
                  --preview-window='right:58%:wrap' | cut -f1) || continue
        [[ -z "$sub" ]] && continue
        _los_menu_run_many "$dir" "$sub" "$want"
        ;;
      logs) _los_menu_logs ;;
      restart) _los_menu_restart_all ;;
      sync-models) _los_menu_sync_models ;;
      model)
        case "$(_los_menu_meta "$dir" "$key" 6)" in
          loaded|sleeping) _los_menu_unload "$port" "$id" ;;
          *) _los_menu_load "$port" "$id" ;;
        esac ;;
      tts)
        case "$(_los_menu_meta "$dir" "$key" 6)" in
          loaded) los-tts unload ;;
          *) los-tts load ;;
        esac ;;
    esac
  done
  rm -rf "$dir"
  return 0
}
