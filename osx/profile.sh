#!/bin/env sh

# When xcode needs to be reinstalled or is corrupted
xcode_reinstall() {
  sudo rm -rf $(xcode-select -print-path)
  xcode-select --install
}

export DOCKER_HOST=unix:///$HOME/.colima/docker.sock

dark() {
  enabled=${1:-true}
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $enabled"
}
