#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

# Omarchy look and feel configs
stow_link hypr
stow_link omarchy
stow_link wireplumber
stow_link alacritty
stow_link alacritty-omarchy
stow_link foot
stow_link nvim

install s-tui  # cli tool for CPU benchmarks

# JetBrains Mono Nerd Font (alacritty terminal font)
if ! pacman -Qq ttf-jetbrains-mono-nerd &>/dev/null; then
  echo -e "${WARN}installing ${NORM}ttf-jetbrains-mono-nerd..."
  sudo pacman -S ttf-jetbrains-mono-nerd --needed --noconfirm
fi

# Offline text-to-speech (speak to the default output via espeak-ng "text")
install espeak-ng

# Keep automatic locking enabled while disabling the optional screensaver.
omarchy-toggle screensaver-off on

# Phone as webcam / second screen (see bin/phone). Bootstrap only when the
# virtual camera module is missing: `phone setup` opens a pkexec dialog, and
# there is nothing to do once the packages are in place, so routine setup runs
# stay silent.
if command -v hyprctl &>/dev/null && ! pacman -Qq v4l2loopback-dkms &>/dev/null; then
  echo -e "${INFO}bootstrapping ${NORM}phone webcam/second-screen support..."
  "$DOT_DIR/bin/phone" setup
fi

# Apply and validate Hyprland configuration when setup runs in a live session.
if command -v hyprctl &>/dev/null && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  echo -e "${INFO}reloading ${NORM}Hyprland configuration..."
  if hyprctl reload; then
    hyprctl configerrors
  else
    echo -e "${WARN}Hyprland reload failed; the configuration will apply on next login.${NORM}"
  fi
fi

echo -e "${PASS}Omarchy setup complete!${NORM}"
