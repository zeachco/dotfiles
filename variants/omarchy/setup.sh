#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

install stow

# Omarchy look and feel configs
cd "$DOT_DIR"
stow --restow waybar
stow --restow hypr

echo -e "${PASS}Omarchy setup complete!${NORM}"
