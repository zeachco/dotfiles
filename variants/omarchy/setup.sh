#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

install stow

# Waybar config
cd "$DOT_DIR"
stow --restow waybar

echo -e "${PASS}Omarchy setup complete!${NORM}"
