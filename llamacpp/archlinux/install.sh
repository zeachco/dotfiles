#!/usr/bin/env bash
#
# Install THE llama.cpp router as a systemd --user service:
#   llama-router.service   :7070, LAN-reachable, ~/models/llama, models.ini,
#                          --no-models-autoload -- every load is an explicit `los`
#
# Until 2026-11-06 there were three (light :7070 / cheap :7071 / heavy :7072). This
# script retires the two extra units when it finds them installed, and moves the old
# per-tier model directories (~/models/light, ~/models/heavy, the ~/models/cheap
# symlinks) into ~/models/llama -- but only once those units are STOPPED, because a
# router keeps its start-time file paths and respawns a sleeping child against them.
#
# Mirrors llamacpp/osx/install.sh: guard, render the template, cmp -s it
# against what is already installed, and skip BEFORE touching the running service
# when nothing changed. Re-running on every `dotfiles_update` is a no-op.
#
# Invoke this with `bash`, not "$SHELL" -- utils.sh runs variant setup scripts as
# `$SHELL <script>`, and under zsh with `set -u`, ${BASH_SOURCE[0]} is unset: the
# SCRIPT_DIR idiom below would print a diagnostic and silently resolve to the
# CALLER's cwd instead of aborting.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
USER_UNIT_DIR="$HOME/.config/systemd/user"
UNIT="llama-router.service"
LEGACY_UNITS=(llama-router-cheap.service llama-router-heavy.service)
MODELS_DIR="$HOME/models/llama"

# ---- guard: never install a unit pointing at a binary that is not there -----------
# The unit itself uses %h (systemd's own specifier), so this checks the same path
# the rendered ExecStart will use without needing to substitute it.
if [[ ! -x "$HOME/dev/llama.cpp/build/bin/llama-server" ]]; then
  echo "llama router skipped: llama-server not built at $HOME/dev/llama.cpp/build/bin/llama-server"
  echo "                      (see docs/ryzen-llm-setup.md for the build steps)"
  exit 0
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "llama router skipped: systemctl is not available"
  exit 0
fi

# ---- knobs -------------------------------------------------------------------------
_require_percent() { # name value
  if ! [[ "$2" =~ ^[0-9]+$ ]] || (($2 < 1 || $2 > 100)); then
    echo "llama router: $1 must be an integer percent from 1-100, got '$2'" >&2
    exit 1
  fi
}
_require_positive() { # name value
  if ! [[ "$2" =~ ^[0-9]+$ ]] || (($2 < 1)); then
    echo "llama router: $1 must be a positive integer, got '$2'" >&2
    exit 1
  fi
}

# Default 90%: leaves headroom for the rest of the desktop during CPU-side work
# (warmup, tokenization, prompt processing that spills off the GPU).
CPU_QUOTA="${LOS_CPU_QUOTA:-90}"
_require_percent LOS_CPU_QUOTA "$CPU_QUOTA"

# Default half the machine's cores, same "leave headroom" reasoning as CPUQuota
# above -- this caps ggml's own thread pool, CPUQuota caps the cgroup as a whole.
HALF_CORES=$(($(nproc) / 2))
((HALF_CORES < 1)) && HALF_CORES=1
THREADS="${LOS_THREADS:-$HALF_CORES}"
_require_positive LOS_THREADS "$THREADS"

# ---- retire the tier units ---------------------------------------------------------
# A unit file left behind would come back on the next login (WantedBy=default.target)
# and advertise models out of a directory this script is about to empty.
legacy_active=()
for u in "${LEGACY_UNITS[@]}"; do
  if systemctl --user is-active --quiet "$u" 2>/dev/null; then
    legacy_active+=("$u")
    continue
  fi
  if [[ -f "$USER_UNIT_DIR/$u" ]] || systemctl --user is-enabled --quiet "$u" 2>/dev/null; then
    systemctl --user disable --now "$u" 2>/dev/null || true
    rm -f "$USER_UNIT_DIR/$u"
    echo "llama router: retired $u"
  fi
done

# ---- one model directory -----------------------------------------------------------
# Renames on one filesystem, so an 88 GiB model moves instantly. Refused while any
# router that was started against the old paths is still up: the light unit has the
# same name as the new one, so "stopped" there means "not running the pre-merge
# ExecStart", which the template cmp below cannot tell apart from a plain restart --
# hence the explicit check on --models-dir in the live process.
_live_models_dir() {
  # The router's argv, straight from /proc: `systemctl show` only reports the unit's
  # ExecStart as written, not what the running process was started with.
  local pid
  pid="$(systemctl --user show -p MainPID --value "$UNIT" 2>/dev/null || true)"
  [[ -n "$pid" && "$pid" != 0 ]] || return 1
  tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null | awk '/^--models-dir$/ { getline; print; exit }'
}

migrate_models() {
  local legacy=() d entry
  for d in "$HOME/models/light" "$HOME/models/heavy"; do
    [[ -d "$d" ]] && [[ -n "$(ls -A "$d" 2>/dev/null)" ]] && legacy+=("$d")
  done
  [[ -d "$HOME/models/cheap" ]] && legacy+=("$HOME/models/cheap")
  ((${#legacy[@]})) || return 0

  if ((${#legacy_active[@]})); then
    echo "llama router: NOT moving ~/models/{light,heavy,cheap} into ~/models/llama while" >&2
    echo "              ${legacy_active[*]} still run(s) against the old paths. Stop them, then" >&2
    echo "              re-run: systemctl --user stop ${legacy_active[*]}; bash $SCRIPT_DIR/install.sh" >&2
    return 0
  fi
  local live
  if live="$(_live_models_dir)" && [[ -n "$live" && "$live" != "$MODELS_DIR" ]]; then
    echo "llama router: NOT moving models while $UNIT serves $live. Stop it (this ends every" >&2
    echo "              loaded model), then re-run: systemctl --user stop $UNIT; bash $SCRIPT_DIR/install.sh" >&2
    return 0
  fi

  mkdir -p "$MODELS_DIR"
  for d in "${legacy[@]}"; do
    if [[ "$d" == "$HOME/models/cheap" ]]; then
      # Only ever held symlinks into light (link_cheap_tier, retired with the tier).
      if [[ -z "$(find "$d" -type f -print -quit 2>/dev/null)" ]]; then
        rm -rf "$d" && echo "llama router: removed ~/models/cheap (symlinks only)"
      else
        echo "llama router: ~/models/cheap holds real files; left for you to sort out" >&2
      fi
      continue
    fi
    for entry in "$d"/* "$d"/.provenance; do
      [[ -e "$entry" || -L "$entry" ]] || continue
      local base="${entry##*/}"
      if [[ "$base" == .provenance ]]; then
        # Per-directory TSV keyed on basename: append rows, never overwrite.
        cat "$entry" >>"$MODELS_DIR/.provenance" && rm -f "$entry"
        continue
      fi
      if [[ -e "$MODELS_DIR/$base" ]]; then
        echo "llama router: $MODELS_DIR/$base already exists; left $entry in place" >&2
        continue
      fi
      mv "$entry" "$MODELS_DIR/" && echo "llama router: moved ${entry#$HOME/} -> ~/models/llama/"
    done
    rmdir "$d" 2>/dev/null || true
  done
}
migrate_models

mkdir -p "$MODELS_DIR" "$HOME/.cache/llama.cpp-router" "$USER_UNIT_DIR"

# ---- render + install the unit ------------------------------------------------------
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

template="$SCRIPT_DIR/$UNIT"
installed="$USER_UNIT_DIR/$UNIT"
rendered="$WORK_DIR/$UNIT"
[[ -f "$template" ]] || { echo "llama router: missing template $template" >&2; exit 1; }

sed -e "s|@CPU_QUOTA@|$CPU_QUOTA|g" -e "s|@THREADS@|$THREADS|g" "$template" >"$rendered"

if grep -q '@[A-Z_]*@' "$rendered"; then
  echo "llama router: unsubstituted token left in $UNIT:" >&2
  grep -n '@[A-Z_]*@' "$rendered" >&2
  exit 1
fi

# Idempotence: bail out before touching the running service.
if [[ -f "$installed" ]] && cmp -s "$rendered" "$installed" && systemctl --user is-active --quiet "$UNIT"; then
  echo "llama router: $UNIT is already installed and running"
else
  install -m 644 "$rendered" "$installed"
  systemctl --user daemon-reload
  echo "llama router: installed $UNIT"
fi

# ---- the resume pair ---------------------------------------------------------------
# los-snapshot.timer records what is resident and llama-router-restore.service replays it
# on every router start (Wants= from the unit). They exist because the router comes back
# from a crash, an oom-kill or a reboot with --no-models-autoload, so it comes back EMPTY
# and every client sees 400 "model is not loaded" until someone runs los-load by hand.
# Neither one is a service you enable to run: the timer drives los-snapshot.service, and
# llama-router-restore.service is pulled in by the router's Wants= each time it starts --
# enabling it would only make it run at boot in its own right.
for aux in los-snapshot.service los-snapshot.timer llama-router-restore.service; do
  aux_tpl="$SCRIPT_DIR/$aux"
  [[ -f "$aux_tpl" ]] || { echo "llama router: missing template $aux_tpl" >&2; exit 1; }
  if cmp -s "$aux_tpl" "$USER_UNIT_DIR/$aux" 2>/dev/null; then
    continue
  fi
  install -m 644 "$aux_tpl" "$USER_UNIT_DIR/$aux"
  aux_changed=1
  echo "llama router: installed $aux"
done
if [[ -n "${aux_changed:-}" ]]; then
  systemctl --user daemon-reload
fi

# enable --now is idempotent and cheap; it also recovers a unit that was installed
# on a previous run but has since been stopped or disabled.
systemctl --user enable --now "$UNIT"
systemctl --user enable --now los-snapshot.timer ||
  echo "llama router: los-snapshot.timer failed to start -- los-restore has nothing to replay" >&2

echo "llama router: http://localhost:7070 (CPUQuota=${CPU_QUOTA}%, threads=${THREADS}, loads on request only: los)"
# A changed unit is installed but NOT restarted: enable --now is a no-op for a running
# unit, and a restart drops in-flight generation. Say so instead of doing it.
if systemctl --user is-active --quiet "$UNIT"; then
  started="$(systemctl --user show -p ExecMainStartTimestamp --value "$UNIT" 2>/dev/null)"
  if [[ -n "$started" ]] && (( $(date -d "$started" +%s 2>/dev/null || echo 0) < $(stat -c %Y "$installed") )); then
    echo "llama router: $UNIT changed since it started -- restart when idle: systemctl --user restart $UNIT"
  fi
fi
echo "llama router: logs with: journalctl --user -u $UNIT -f"

if [[ -z "$(ls -A "$MODELS_DIR" 2>/dev/null || true)" ]]; then
  echo "llama router: ~/models/llama is empty. Fetch the model set with:"
  echo "              bash ${DOT_DIR:-$HOME/dotfiles}/llamacpp/archlinux/fetch-models.sh"
fi

# Cheap integrity pass on every setup run: header + size of each GGUF against the
# digest row recorded at fetch time. Seconds, no full read -- that is --full, run
# once at the end of every fetch run and by hand for a bitrot sweep (--offline).
if [[ -n "$(find "$HOME/models" -name '*.gguf' -print -quit 2>/dev/null)" ]]; then
  bash "$SCRIPT_DIR/../shared/verify-models.sh" --quick --dir "$HOME/models" ||
    echo "llama router: model verification FAILED -- see above; re-fetch the named file(s)"
fi
