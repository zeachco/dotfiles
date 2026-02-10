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

docker() {
  # Use local variable to avoid scope issues in subshells
  local docker_bin="/opt/homebrew/bin/docker"

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

