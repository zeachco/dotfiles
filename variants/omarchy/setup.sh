#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

# Omarchy look and feel configs
stow_link waybar
stow_link hypr
stow_link claude

echo -e "${PASS}Omarchy setup complete!${NORM}"
