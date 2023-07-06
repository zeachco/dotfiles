#!/bin/env bash
source ~/dotfiles/utils.sh

script_install fzf "git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install --completion --key-bindings --update-rc"
script_install lvim "bash <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh) --no-install-dependencies && sudo ln -s ~/.local/bin/lvim /usr/bin/lvim"
