#!/usr/bin/env bash
# Clone only; platform setup remains responsible for builds and router services.
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
  if [[ -e "$target" || -L "$target" ]]; then
    echo "llama.cpp: found $target; skipping clone"
    return 0
  fi

  # Decimal 16 GB accommodates memory reserved by GPU drivers on 16 GiB cards.
  # Require one qualifying device/pool; do not sum unrelated GPUs or CPU RAM.
  if ! llama_memory_sizes | awk '
    /^[0-9]+$/ && $1 >= 16000000000 { enough = 1 }
    END { exit !enough }
  '; then
    echo "llama.cpp: skipping clone (no detected VRAM/unified memory pool >= 16 GB)"
    return 0
  fi

  echo "llama.cpp: cloning into $target"
  mkdir -p "$HOME/dev" || return 1
  git clone https://github.com/ggml-org/llama.cpp.git "$target"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  clone_llama_cpp
fi
