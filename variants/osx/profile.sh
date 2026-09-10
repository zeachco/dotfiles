#!/bin/sh

# When xcode needs to be reinstalled or is corrupted
xcode_reinstall() {
  sudo rm -rf "$(xcode-select -print-path)"
  xcode-select --install
}

dark() {
  enabled=${1:-true}
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $enabled"
}

# In conjunction with the shared install that uses brew on osx
source $(brew --prefix)/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh

docker() {
  # Use local variable to avoid scope issues in subshells
  local docker_bin="$(which docker 2>/dev/null || echo "${HOMEBREW_PREFIX:-/usr/local}/bin/docker")"

  # Ensure docker is installed
  which docker >/dev/null || brew install docker

  # Ensure colima is installed
  which colima >/dev/null || { brew install colima && sleep 1; }

  # Start colima if docker daemon isn't responding
  $docker_bin version >/dev/null 2>&1 || {
    colima start && sleep 1
    DOCKER_HOST=$(colima status -j 2>/dev/null | jq -r '.docker_socket')
    export DOCKER_HOST
  }

  $docker_bin "$@"
}

# --- llama.cpp router (launchd agent com.zeachco.llama-router) --------------------
# The router's environment lives in its plist's EnvironmentVariables, so nothing needs
# re-applying here on each shell start.
#
# These are los-PREFIXED helpers, deliberately not a redefinition of `los` --
# llamacpp/shared/_llama.sh owns `los-server-light`/`los-server-heavy`/`los-server-cheap` as the foreground
# launchers and `los` is the fzf menu in _los_menu.sh; these wrap the launchd agent instead.
LOS_LABEL="com.zeachco.llama-router"
LOS_URL="http://127.0.0.1:7070"
LOS_LOG="$HOME/Library/Logs/llama-router/router.log"
LOS_INI="$HOME/dotfiles/llamacpp/osx/osx.ini"

_los_target() { echo "gui/$(id -u)/$LOS_LABEL"; }

# Loaded? running? answering? A climbing pid with a non-zero "last exit code" is the
# crash-loop signature (KeepAlive + ThrottleInterval 10).
los-status() {
  launchctl print "$(_los_target)" 2>/dev/null |
    grep -E '^[[:space:]]+(state|pid|program|last exit) ' ||
    { echo "$LOS_LABEL is not loaded"; return 1; }
  echo "--- $LOS_URL/health ---"
  curl -fsS --max-time 3 "$LOS_URL/health" || echo "(no answer on $LOS_URL)"
}

# kickstart -k restarts whether or not the job is currently running, which
# `launchctl stop` followed by `start` does not reliably do.
los-restart() {
  launchctl kickstart -k "$(_los_target)" && echo "restarted $LOS_LABEL"
}

# stdout and stderr share one file on purpose: a failed model load interleaves banners
# (stdout) with the actual error (stderr), and split files lose the ordering.
los-logs() { tail -n "${1:-80}" -f "$LOS_LOG"; }

# Every id the router will accept -- the AUTHORITATIVE list. For a model in a
# subdirectory the id is the DIRECTORY name, not the .gguf stem.
los-models() { curl -fsS "$LOS_URL/v1/models" | jq -r '.data[].id'; }

# Diff osx.ini's section names against reality. A section matching no id is ignored
# with NO warning and the model falls back to [*] or to a 4096-token default, which is
# the highest-probability silent failure in this setup -- hence a dedicated command.
# Left-only lines are dead sections; right-only lines are models on [*] defaults.
los-check() {
  diff <(sed -n 's/^\[\([^*][^]]*\)\]$/\1/p' "$LOS_INI" | sort) \
       <(los-models | sort) &&
    echo "osx.ini sections match the router's model ids"
}

# Which ids are currently RESIDENT. --models-max is 4 and only three models exist, so
# the router never evicts (eviction is by model COUNT, never bytes): los-unload is the
# only way to give memory back.
los-loaded() { curl -fsS "$LOS_URL/models" | jq .; }
los-unload() {
  curl -fsS -X POST "$LOS_URL/models/unload" \
    -H 'content-type: application/json' -d "{\"model\":\"$1\"}"
}

# The Metal wired limit is the binding constraint on how many models fit. It resets to
# 0 on every reboot, which is why com.zeachco.iogpu-limit exists to re-apply it.
los-mem() {
  echo "iogpu.wired_limit_mb = $(sysctl -n iogpu.wired_limit_mb)  (0 = default, ~36 GiB of 48)"
  sysctl vm.swapusage
  ps -Ao pid,ppid,rss,%cpu,comm | grep -E 'llama' | grep -v grep
}
