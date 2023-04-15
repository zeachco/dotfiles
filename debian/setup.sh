#!/bin/env bash
source ~/dotfiles/utils.sh

install neofetch

# linux based spin envs are already configured
if [ -d /opt/spin ]
then
    echo -e "${FAIL}Not installing debian packages for spin linux machine"
    exit 0
fi

neovimVersion=$(nvim --version | head -n 1 | awk '{print $2}')

if [ "$(echo "${neovimVersion} v0.8" | tr " " "\n" | sort -V | tail -n 1)" = "${neovimVersion}" ]
then
    print_exists "neovim $neovimVersion"
else
    print_needs "neovim 0.8+"
    { # try
        sudo apt remove -y neovim
        sudo add-apt-repository ppa:neovim-ppa/unstable
        sudo apt update -y
    } || { # catch
        echo -e "${FAIL} Not updating apt cache ${NORM}"
    }
    install neovim
fi

# tools
install zsh
install tmux
install ifconfig net-tools
install dig dnsutils
install curl
install htop
install g++
install make

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
