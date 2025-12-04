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

# Set original_docker to the actual docker binary path
original_docker="/opt/homebrew/bin/docker"

docker() {
  which colima >/dev/null || { brew install colima && sleep 1; } # ensures we have colima
  $original_docker version >/dev/null || {
    colima start && sleep 1
    DOCKER_HOST=$(colima status -j 2>/dev/null | jq -r '.docker_socket')
    export DOCKER_HOST
  }
  $original_docker "$@"
}

