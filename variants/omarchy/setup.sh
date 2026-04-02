#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

install stow

# Omarchy look and feel configs
stow_package waybar
stow_package hypr
stow_package claude

echo -e "${PASS}Omarchy setup complete!${NORM}"
