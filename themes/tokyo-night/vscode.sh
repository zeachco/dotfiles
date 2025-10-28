#!/bin/bash

VSC_THEME="Tokyo Night"
VSC_EXTENSION="enkia.tokyo-night"

if command -v code &>/dev/null; then
  echo "  → Installing VS Code extension: $VSC_EXTENSION"
  code --install-extension "$VSC_EXTENSION" >/dev/null 2>&1

  # Update settings.json
  if [ -f "$HOME/.config/Code/User/settings.json" ]; then
    sed -i.bak "s/\"workbench.colorTheme\": \".*\"/\"workbench.colorTheme\": \"$VSC_THEME\"/g" \
      "$HOME/.config/Code/User/settings.json"
    rm -f "$HOME/.config/Code/User/settings.json.bak"
  fi
fi
