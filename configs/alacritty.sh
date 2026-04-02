rm -rf .config/alacritty

# Check if running on Omarchy (detect hyprland config)
if [ -d ~/.config/hypr ]; then
  # Install no-panel layout for zellij
  mkdir -p ~/.config/zellij/layouts
  cp ~/dotfiles/configs/zellij-no-panel.kdl ~/.config/zellij/layouts/no-panel.kdl

  # On Omarchy: create separate config file for zellij profile
  if [ "$(uname -s)" = "Darwin" ]; then
    FONT_SIZE=16.0
  else
    FONT_SIZE=12.0
  fi

  cat >~/.dotfiles_alacritty.toml <<EOF

[terminal.shell]
program = "$(which zellij)"
args = ["--layout", "$HOME/.config/zellij/layouts/no-panel.kdl"]

[window]
padding = { x = 10, y = 10 }

[font]
size = \${FONT_SIZE}
EOF

  # Add hypr binding for super+enter to use this config
  BINDINGS_FILE=~/.config/hypr/bindings.conf
  if [ -f "$BINDINGS_FILE" ]; then
    # Check if binding already exists
    if ! grep -q "dotfiles_alacritty" "$BINDINGS_FILE"; then
      # Add the binding after the terminal binding (line 5)
      sed -i '5 a bindd = SUPER, RETURN, Terminal with Zellij, exec, uwsm-app -- alacritty --config-file ~/.dotfiles_alacritty.toml' "$BINDINGS_FILE"
    fi
  fi
else
  # Non-Omarchy: create default alacritty config with zellij
  if [ "$(uname -s)" = "Darwin" ]; then
    FONT_SIZE=13.0
  else
    FONT_SIZE=11.0
  fi

  cat >~/.alacritty.toml <<EOF
[general]
import = ["~/dotfiles/configs/alacritty.toml"]

[terminal.shell]
program = "$(which zellij)"
# args = ["attach", "--create", "1"]

[font]
size = \${FONT_SIZE}

[font.normal]
family = "VictorMono Nerd Font"
style = "Regular"

[font.bold]
family = "VictorMono Nerd Font"
style = "Bold"

[font.italic]
family = "VictorMono Nerd Font"
style = "Italic"
#
EOF
fi
