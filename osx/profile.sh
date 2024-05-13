#!/bin/env sh

# When xcode needs to be reinstalled or is corrupted
xcode_reinstall() {
  sudo rm -rf $(xcode-select -print-path)
  xcode-select --install
}

# alias with command print
_set () {
  alias $1="echo -e \" ~ \033[0;34m$2\033[0m\" && $2"
}
