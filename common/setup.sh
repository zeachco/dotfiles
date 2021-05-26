#!/bin/bash

# # DIR="$HOME/.cli-dev"



# APPS="zsh neovim tmux net-tools curl htop g++ make"
# echo "this script is meant to be used on a debian-type os like Ubuntu"
# read -n 1 -p  "Press any key to continue"

# # tools
# eval "sudo apt install -y $APPS"

# # omzsh
# sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# # fzf
# git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
# ~/.fzf/install

# # sudo setcap 'cap_net_bind_service=+ep' `which node`
# # echo "Changing max notify watcher from $(cat /proc/sys/fs/inotify/max_user_watches) to 524288 (max value)"
# # echo "fs.inotify.max_user_watches=524288" | sudo tee -a  /etc/sysctl.conf

# read -p "Email for git config: " git_email
# read -p "Full name for git config: " git_name

# git config --global --replace-all user.email $git_email
# git config --global --replace-all user.name $git_name
git config --global --replace-all credential.helper cache

git config --global --replace-all color.ui auto
git config --global --replace-all alias.b "branch -a"
git config --global --replace-all alias.aaa "add . --all && commit --amend --no-edit"
git config --global --replace-all alias.rbi "rebase upstream/master -i"
git config --global --replace-all alias.ph "push heroku master"
git config --global --replace-all alias.aa "add -A"
git config --global --replace-all alias.d "diff"
git config --global --replace-all alias.s "status"
git config --global --replace-all alias.co "checkout"
git config --global --replace-all alias.cp "cherry-pick"
git config --global --replace-all alias.ci "commit"
git config --global --replace-all alias.rb "rebase -i"
git config --global --replace-all alias.p "pull"
git config --global --replace-all alias.pp "push origin"
git config --global --replace-all alias.fa "fetch --all"
git config --global --replace-all alias.fu "fetch upstream"
git config --global --replace-all alias.rh "reset --hard"
git config --global --replace-all alias.mt "mergetool"
git config --global --replace-all core.editor "nvim"
git config --global --replace-all push.default "tracking"
git config --global --replace-all alias.l "log --oneline --graph"

# # echo "Setting up '$DIR/profile.sh'"
# # chmod +x "$DIR/profile.sh"
# # echo "source $DIR/profile.sh" >> ~/.zprofile
# # source "$DIR/profile.sh"

# # ln -sf ~/.vim/plugins.vim ~/.cli-dev/plugins.vim
# # ln -sf ~/.config/nvim/init.vim ~/.cli-dev/nvim.vim
