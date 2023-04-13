#!/bin/env bash
source ~/dotfiles/utils.sh

_add_zsh_variant debian

RED="\033[0;31m;"
NC="\033[0m;"


install() {
    if command -v apt &> /dev/null
    then
        sudo apt install -y $1
    else
        if command -v pacman &> /dev/null
        then
            sudo pacman -S $1 --noconfirm
        else
            echo -e "${RED} I don't know how to install $1 ${NC}"
        fi
    fi
}


# linux based spin envs are already configured
if [ -d /opt/spin ]; then
    install neofetch
    echo "Not installing debian packages for spin linux machine"
    exit 0
fi

neovimVersion=$(nvim --version | head -n 1 | awk '{print $2}')

if [ "$(echo "${neovimVersion} v0.8" | tr " " "\n" | sort -V | tail -n 1)" = "${neovimVersion}" ]; then
    echo "Using neovim $neovimVersion"
else
    echo "Neovim version is lower than 0.8, updating"

    { # try
        sudo apt remove -y neovim
        sudo add-apt-repository ppa:neovim-ppa/unstable
        sudo apt update -y
    } || { # catch
        echo -e "${RED} Not updating apt cache ${NC}"
    }
    install neovim
fi

# tools
install zsh
install tmux
install net-tools
install curl
install htop
install g++
install make
install neofetch

# omzsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

if [ `command -v fzf` ] ; then
    echo "fzf already installed"
else
    echo "installing fzf"
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --completion --key-bindings --update-rc
fi

## install lunarvim

bash <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh) --no-install-dependencies
sudo ln -s ~/.local/bin/lvim /usr/bin/lvim

download_fonts() {
    FONT=VictorMono
    
    mkdir -p ~/.local/share/fonts/$FONT
    cd ~/.local/share/fonts/$FONT
    
    curl -fLo "$FONT Nerd Font Complete.otf" "https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/$FONT/complete/$FONT%20Nerd%20Font%20Complete.otf"
    
    
    # NAME=BorgSansMono
    # FILE=$NAME.ttf.zip
    # FONT_LINK=https://github.com/marnen/borg-sans-mono/files/107663/$FILE
    
    
    # wget $FONT_LINK
    # unzip $FILE -d $NAME
    
    # mkdir -p ~/.local/share/fonts/$NAME
    # cp $NAME/*.ttf ~/.local/share/fonts/$NAME/
    
    fc-cache -f -v
}

download_fonts
