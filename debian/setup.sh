#!/bin/env bash
source ~/dotfiles/utils.sh

_add_zsh_variant debian

# linux based spin envs are already configured
if [ -d /opt/spin ]; then
    echo "Not installing debian packages for spin linux machine"
    exit 0
fi

APPS="zsh neovim tmux net-tools curl htop g++ make neofetch"

# tools
eval "sudo apt install -y $APPS"

# omzsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# fzf
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install


## install lunarvim

bash <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh) --no-install-dependencies
