#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

# Assuming Ubuntu is using Omakub

# tools
install unzip
install ifconfig net-tools
install dig dnsutils
install g++
install make

script_install devbox "curl -fsSL https://get.jetify.com/devbox | $SHELL"

stow_link claude

$SHELL ~/dotfiles/ubuntu/shortcuts.sh
