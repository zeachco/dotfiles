#!/usr/bin/env bash
# Clone and start initial model downloads; platform setup handles builds/services.
# Run with bash explicitly, including when the user's login shell is zsh.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_hw-gate.sh"

llama_memory_sizes() {
  local file
  if is_apple_silicon; then
    _hw_sysctl hw.memsize
  elif [[ "$(uname -s)" == Linux ]]; then
    # Count system RAM only on known unified-memory hardware, not CPU-only hosts.
    if is_ryzen_ai_max; then
      awk '/^MemTotal:/ { printf "%.0f\n", $2 * 1024 }' /proc/meminfo
    fi
    if command -v nvidia-smi >/dev/null 2>&1; then
      nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null |
        awk '$1 ~ /^[0-9]+$/ { printf "%.0f\n", $1 * 1048576 }'
    fi
    # AMDGPU reports VRAM in bytes. GTT is pageable host RAM, not extra VRAM.
    # https://www.kernel.org/doc/html/latest/gpu/amdgpu/driver-misc.html
    for file in /sys/class/drm/card*/device/mem_info_vram_total; do
      [[ -r "$file" ]] && cat "$file"
    done
  fi
  return 0
}

clone_llama_cpp() {
  local target="$HOME/dev/llama.cpp"
  # Decimal 16 GB accommodates memory reserved by GPU drivers on 16 GiB cards.
  # Require one qualifying device/pool; do not sum unrelated GPUs or CPU RAM.
  if ! llama_memory_sizes | awk '
    /^[0-9]+$/ && $1 >= 16000000000 { enough = 1 }
    END { exit !enough }
  '; then
    echo "llama.cpp: skipping clone/downloads (no detected VRAM/unified memory pool >= 16 GB)"
    return 0
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    echo "llama.cpp: found $target; skipping clone"
  else
    echo "llama.cpp: cloning into $target"
    mkdir -p "$HOME/dev" || return 1
    git clone https://github.com/ggml-org/llama.cpp.git "$target" || return 1
  fi

  # Gate on CONTENT, not on the directory existing. The Arch install.sh mkdir -p's
  # ~/models/{light,cheap,heavy} for the systemd units, so on any box where it has run
  # once an existence test is always true and the download never starts -- which is
  # exactly what happened on the 2026-09-14 reinstall: three empty tier dirs, three
  # routers advertising light.ini names with no --model, every load spinning forever.
  # Same directory logic as fetch-initial-models.sh, which is what gets launched.
  local models="$HOME/models/light"
  [[ "$(uname -s)" == Darwin ]] && models="${LOS_MODELS_DIR:-$HOME/models}"
  if [[ -n "$(find "$models" -name '*.gguf' -print -quit 2>/dev/null)" ]]; then
    echo "llama.cpp: found models under $models; skipping model downloads"
    return 0
  fi

  local log_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
  mkdir -p "$log_dir" "$HOME/models" || return 1

  # mkdir ~/models used to be the lock; it cannot be once the dir may pre-exist. A pid
  # file under ~/models, created with noclobber so two concurrent setups cannot both win,
  # and checked for liveness so a crashed job does not block the next run forever.
  local lock="$HOME/models/.initial-downloads.pid" pid
  if pid="$(cat "$lock" 2>/dev/null)" && [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "llama.cpp: model download already running (PID $pid); skipping"
    echo "llama.cpp: download log: $log_dir/llamacpp-model-download.log"
    return 0
  fi
  rm -f "$lock"
  if ! ( set -C; echo $$ >"$lock" ) 2>/dev/null; then
    echo "llama.cpp: another setup is starting the model download; skipping"
    return 0
  fi

  # The wrapper owns the lock: it is removed when fetch-initial-models.sh exits, however
  # it exits, so a finished or failed job never reads as "already running".
  nohup bash -c 'trap "rm -f \"$1\"" EXIT; bash "$2"' _ "$lock" "$SCRIPT_DIR/fetch-initial-models.sh" \
    >"$log_dir/llamacpp-model-download.log" 2>&1 </dev/null &
  echo $! >"$lock"
  echo "llama.cpp: model downloads started (PID $!)"
  echo "llama.cpp: download log: $log_dir/llamacpp-model-download.log"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  clone_llama_cpp
fi
