# Hardware gate for the llama.cpp setup. SOURCED, not executed.
#
# Only two machines in this repo run local models: the Apple Silicon Mac (Metal,
# unified memory) and the Strix Halo desktop (Vulkan, 128 GiB unified memory).
# Every other host that runs `dotfiles_update` -- Intel Macs, x86 laptops, Termux,
# a bare Arch server -- has no business brew-installing llama.cpp, installing a
# router service, or spending 32 cores on a rebuild. These predicates are the one
# place that decision is made, so the Mac and the Arch box cannot drift apart.
#
# PORTABILITY: macOS ships bash 3.2.57 with no Homebrew bash, so nothing here may
# use associative arrays, ${var,,}, mapfile/readarray or globstar.

# `sysctl` lives in /usr/sbin, which is NOT on PATH inside a devbox or nix shell --
# and variants/shared/profile.sh auto-enters devbox shells on cd, so `dotfiles_update`
# run from one saw no sysctl at all and skipped an M4 Pro outright. Absolute path
# first, PATH lookup second.
_hw_sysctl() {
  if [[ -x /usr/sbin/sysctl ]]; then
    /usr/sbin/sysctl -n "$1" 2>/dev/null
  else
    sysctl -n "$1" 2>/dev/null
  fi
}

# Apple Silicon (any M-series), i.e. a Metal-accelerated llama.cpp build.
#
# Three signals, any one of which is enough, because each has a hole:
#   * machdep.cpu.brand_string is the most specific ("Apple M4 Pro") and survives
#     Rosetta 2 translation, where `uname -m` reports x86_64 on an M-series box.
#   * hw.optional.arm64 covers a future rename that drops the "Apple M" prefix.
#   * `uname -m` is the last resort: /usr/bin/uname is always reachable, so this is
#     what answers when sysctl cannot be found at all. It is the one signal Rosetta
#     gets wrong, hence last.
is_apple_silicon() {
  [[ "$(uname -s)" == Darwin ]] || return 1

  case "$(_hw_sysctl machdep.cpu.brand_string)" in
  "Apple M"*) return 0 ;;
  esac

  [[ "$(_hw_sysctl hw.optional.arm64)" == "1" ]] && return 0

  [[ "$(uname -m)" == "arm64" ]]
}

# Ryzen AI MAX (Strix Halo). Deliberately matched as "RYZEN AI MAX" rather than the
# full "MAX+ 395 w/ Radeon 8060S" string, so a 385 or a BIOS that reformats the model
# name still matches. Any other Ryzen -- a desktop 7950X, a laptop 7840U -- is NOT a
# local-LLM box here: the whole setup assumes a big iGPU sharing system RAM.
is_ryzen_ai_max() {
  [[ -r /proc/cpuinfo ]] || return 1
  grep -qi "ryzen ai max" /proc/cpuinfo 2>/dev/null
}
