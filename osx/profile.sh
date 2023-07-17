#!/bin/env bash

xcode_kill() {
  sudo rm -rf $(xcode-select -print-path)
  xcode-select --install
}

function _set () {
  alias $1="echo -e \" ~ \033[0;34m$2\033[0m\" && $2"
}

_set bank "spin up ~/sbanking.yml --wait"
