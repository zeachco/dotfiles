#!/bin/env bash
source ~/dotfiles/utils.sh

# linux based spin envs are already configured
if [[ ls /opt/spin ]]; then
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

# allows node to run on admin ports such as 80 and 443
sudo setcap 'cap_net_bind_service=+ep' `which node`
echo "Changing max notify watcher from $(cat /proc/sys/fs/inotify/max_user_watches) to 524288 (max value)"
echo "fs.inotify.max_user_watches=524288" | sudo tee -a  /etc/sysctl.conf

_add_zsh_variant debian
