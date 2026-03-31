#!/bin/sh

# hack to remap caps lock to escape
# setxkbmap -option caps:escape

wifi() {
  lspci -nnk | grep -iA2 net
}

kde_restart() {
  sudo systemctl restart display-manager
}

zapt() {
  package="$(
    apt-cache pkgnames |
      fzf -m --prompt="Enter Package Names: " \
        --preview "apt show {} 2>/dev/null" \
        --preview-window 'top:75%' |
      tr "\n" " "
  )"
  [[ $package ]] && read -n1 -p "Install ${package}? [y/N]: " install
  [[ "$install" == "y" ]] && sudo apt install $package
}
