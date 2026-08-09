#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

# Omarchy look and feel configs
stow_link waybar
stow_link hypr
stow_link claude
stow_link wireplumber
stow_link alacritty
stow_link alacritty-omarchy
stow_link nvim
stow_link zellij-omarchy

install s-tui  # cli tool for CPU benchmarks

# Load dotfiles-owned window rules from Omarchy's user config entrypoint.
HYPRLAND_CONFIG=~/.config/hypr/hyprland.conf
WINDOW_RULES_SOURCE='source = ~/.config/hypr/windowrules.conf'
if [ -f "$HYPRLAND_CONFIG" ] && ! grep -Fqx "$WINDOW_RULES_SOURCE" "$HYPRLAND_CONFIG"; then
  sed -i "/# Toggle config flags dynamically/i $WINDOW_RULES_SOURCE\n" "$HYPRLAND_CONFIG"
fi

# Add hypr binding for alacritty with custom zellij layout
BINDINGS_FILE=~/.config/hypr/bindings.conf
if [ -f "$BINDINGS_FILE" ]; then
  if ! grep -q "dotfiles_alacritty" "$BINDINGS_FILE"; then
    # Add the binding for custom alacritty config
    sed -i '5 a bindd = SUPER, RETURN, Terminal with Zellij, exec, uwsm-app -- alacritty --config-file ~/.dotfiles_alacritty.toml' "$BINDINGS_FILE"
  fi
fi

echo -e "${PASS}Omarchy setup complete!${NORM}"
