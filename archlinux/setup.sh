#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

# tools
install unzip
# install net-tools
# install bind-tools  # for dig
install curl
install htop
install gcc
install make
install zellij
install zsh

script_install ollama "curl -fsS https://ollama.com/install.sh | $SHELL"

# Check neovim version and install/update if needed
neovimVersion=$(nvim --version 2>/dev/null | head -n 1 | awk '{print $2}' || echo "0.0.0")

if [ "$(echo "${neovimVersion} v0.8" | tr " " "\n" | sort -V | tail -n 1)" = "${neovimVersion}" ]
then
    print_exists "neovim $neovimVersion"
else
    print_needs "neovim 0.8+"
    install neovim
fi

# Install VictorMono Nerd Font
FONT=VictorMono
if [ -d "$HOME/.local/share/fonts/$FONT" ]
then
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
sudo pacman -Syu --noconfirm

# Install yay (AUR helper) if not present
if ! command -v yay &> /dev/null
then
    echo -e "${WARN}installing yay (AUR helper)...${NORM}"
    sudo pacman -S --needed git base-devel --noconfirm
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd -
    rm -rf /tmp/yay
fi

install flatpak
if ! flatpak list --app 2>/dev/null | grep -q com.ktechpit.orion; then
    echo -e "${WARN}installing ${NORM}orion..."
    flatpak install -y flathub com.ktechpit.orion
else
    print_exists orion
fi

install fd
install fzf
install bat
install exa
install starship
script_install bw "install bitwarden-cli"

# Configure mpv for Orion (Flatpak) - fix black video on Wayland
mkdir -p ~/.var/app/com.ktechpit.orion/config/mpv
echo "vo=wlshm" > ~/.var/app/com.ktechpit.orion/config/mpv/mpv.conf

echo -e "${PASS}Arch Linux setup complete!${NORM}"
