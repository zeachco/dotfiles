#!/bin/env bash
source ~/dotfiles/utils.sh

_add_zsh_variant spin


if [ `command -v fzf` ] ; then
    echo "fzf already installed"
else
    echo "installing fzf"
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --completion --key-bindings --update-rc
fi

bash <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh) --no-install-dependencies
sudo ln -s ~/.local/bin/lvim /usr/bin/lvim
