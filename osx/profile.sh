#!/bin/env sh

# When xcode needs to be reinstalled or is corrupted
xcode_reinstall() {
  sudo rm -rf $(xcode-select -print-path)
  xcode-select --install
}

export DOCKER_HOST=unix:///$HOME/.colima/docker.sock

