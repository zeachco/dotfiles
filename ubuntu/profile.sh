#!/bin/env sh

# hack to remap caps lock to escape
# setxkbmap -option caps:escape

wifi() {
  lspci -nnk | grep -iA2 net
}

kde_restart() {
  sudo systemctl restart display-manager
}
