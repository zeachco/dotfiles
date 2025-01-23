#!/bin/env sh
source ~/dotfiles/utils.sh

# Assuming Ubuntu is using Omakub

install neofetch

# tools
install unzip
install ifconfig net-tools
install dig dnsutils
install htop
install g++
install make

script_install devbox "curl -fsSL https://get.jetify.com/devbox | $SHELL"

$SHELL ~/dotfiles/ubuntu/shortcuts.sh
