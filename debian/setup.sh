#!/bin/env bash
source ~/dotfiles/utils.sh

_add_zsh_variant debian

# linux based spin envs are already configured
if [ -d /opt/spin ]; then
    sudo apt install -y neofetch
    echo "Not installing debian packages for spin linux machine"
    exit 0
fi

# Update or install neovim
if (( $(nvim --version | head -n 1 | awk '{print $2}') >= 0.8 )); then
    echo "Neovim version is 0.8 or higher"
else
    echo "Neovim version is lower than 0.8"
    sudo apt remove -y neovim
    sudo add-apt-repository ppa:neovim-ppa/unstable
    sudo apt update -y
    sudo apt install -y neovim
fi

APPS="zsh tmux net-tools curl htop g++ make neofetch"

# tools
eval "sudo apt install -y $APPS"

# omzsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# fzf
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install


## install lunarvim

bash <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh) --no-install-dependencies
sudo ln -s ~/.local/bin/lvim /usr/bin/lvim

download_fonts() {
    NAME=BorgSansMono
    FILE="$NAME.ttf.zip"
    FONT_LINK="https://github.com/marnen/borg-sans-mono/files/107663/$FILE"
    
    mkdir -p ~/.local/share/fonts
    cd ~/.local/share/fonts
    
    wget "$FONT_LINK"
    unzip "$FILE" -d "$NAME"
    
    mkdir -p "~/.local/share/fonts/$NAME"
    cp "$NAME/*.ttf" "~/.local/share/fonts/$NAME/"
    
    fc-cache -f -v
}

download_fonts
