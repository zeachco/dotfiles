#!/bin/env bash
source ~/dotfiles/utils.sh

_add_zsh_variant common

function configureGitIdentity() {
    echo "Email for git config: "
    read git_email
    echo "Full name for git config: "
    read git_name
    git config --global --replace-all user.email $git_email
    git config --global --replace-all user.name $git_name
}

foundEmail=`git config --list | grep email`

if [[ $foundEmail != *"@"* ]]
    then configureGitIdentity
fi

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
git config --global --replace-all pull.rebase true

icurl -fsSL https://deno.land/x/install/install.sh | sh
curl https://pyenv.run | bash

