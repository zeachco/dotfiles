#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

# tools
install unzip
# install net-tools
# install bind-tools  # for dig
install curl
install gcc
install make
install zellij
install zsh
install s-tui # cli tool for CPU benchmarks

script_install ollama "curl -fsS https://ollama.com/install.sh | $SHELL"

# Check neovim version and install/update if needed
neovimVersion=$(nvim --version 2>/dev/null | head -n 1 | awk '{print $2}' || echo "0.0.0")

if [ "$(echo "${neovimVersion} v0.8" | tr " " "\n" | sort -V | tail -n 1)" = "${neovimVersion}" ]; then
  print_exists "neovim $neovimVersion"
else
  print_needs "neovim 0.8+"
  install neovim
fi

# Install VictorMono Nerd Font
FONT=VictorMono
if [ -d "$HOME/.local/share/fonts/$FONT" ]; then
  print_exists "VictorMono Font"
else
  print_needs "VictorMono Font"
  mkdir -p ~/.local/share/fonts/$FONT
  cd ~/.local/share/fonts/$FONT
  curl -fLo "$FONT Nerd Font Complete.otf" "https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/$FONT/complete/$FONT%20Nerd%20Font%20Complete.otf"
  fc-cache -f -v
fi

# System update
echo -e "${WARN}updating system packages...${NORM}"
if command -v omarchy &>/dev/null; then
  # Omarchy handles its own privilege escalation; -y runs unattended like --noconfirm
  omarchy update -y
else
  sudo pacman -Syu --noconfirm
fi

# Install yay (AUR helper) if not present
if ! command -v yay &>/dev/null; then
  echo -e "${WARN}installing yay (AUR helper)...${NORM}"
  sudo pacman -S --needed git base-devel --noconfirm
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay
  makepkg -si --noconfirm
  cd -
  rm -rf /tmp/yay
fi

install flatpak
install fd
install fzf
install bat
install exa
install starship
script_install bw "install bitwarden-cli"

install avahi-browse avahi
install cvlc vlc-cli

# VLC 3 is split into optional plugins on Arch. Chromecast output needs these
# plugins for device support, media decoding, and H.264 transcoding.
for package in vlc-plugin-chromecast vlc-plugin-ffmpeg vlc-plugin-x264; do
  if pacman -Q "$package" >/dev/null 2>&1; then
    print_exists "$package"
  else
    sudo pacman -S "$package" --needed --noconfirm
  fi
done

# Configure WirePlumber - Sound Blaster GS5 analog stereo profile
# Prevents pro-audio mode from stealing the sound device between apps
stow_link wireplumber
stow_link alacritty
stow_link alacritty-archlinux
stow_link nvim
stow_link opencode

echo -e "${PASS}Arch Linux setup complete!${NORM}"
