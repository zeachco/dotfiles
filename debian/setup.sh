#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

install neofetch

# linux based spin envs are already configured
if [ -d /opt/spin ]
then
    echo -e "${FAIL}Not installing debian packages for spin linux machine"
    exit 0
fi
# tools
install unzip
# install gdebi
# install zsh
install tmux
install ifconfig net-tools
install dig dnsutils
install curl
install htop
install g++
install make
install gh github-cli
script_install ollama "curl -fsS https://ollama.com/install.sh | $SHELL"


# just use omakub
exit 0;
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

## run system updates

echo -e "${WARN}installing ${NORM}$pkg_name..."
if command -v apt &> /dev/null
then
    sudo apt update
    sudo apt upgrade -y
else
    if command -v pacman &> /dev/null
    then
        sudo pacman -Syu
    else
        echo -e "${FAIL} I don't know how to update this system ${NORM}"
    fi
fi

# echo "Remapping CapsLock to ESC"
# echo "setxkbmap -option caps:escape" >> ~/.xinitrc
