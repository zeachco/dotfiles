#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

configureGitIdentity() {
  echo "Email for git config: "
  read git_email
  echo "Full name for git config: "
  read git_name
  git config --global --replace-all user.email $git_email
  git config --global --replace-all user.name $git_name
}

foundEmail=$(git config --list | grep email)

if [[ $foundEmail != *"@"* ]]; then
  configureGitIdentity
fi

git config --global --replace-all credential.helper cache
git config --global --replace-all color.ui auto
git config --global --replace-all alias.b "branch -a"
git config --global --replace-all alias.aaa "add . --all && commit --amend --no-edit"
git config --global --replace-all alias.rbi "rebase upstream/master -i"
git config --global --replace-all alias.aa "add -A"
git config --global --replace-all alias.d "diff"
git config --global --replace-all alias.s "status"
git config --global --replace-all alias.co "checkout"
git config --global --replace-all alias.cp "cherry-pick"
git config --global --replace-all alias.ci "commit"
git config --global --replace-all alias.rb "rebase -i"
git config --global --replace-all alias.p "pull"
git config --global --replace-all alias.pp "push"
git config --global --replace-all alias.fa "fetch --all"
git config --global --replace-all alias.fu "fetch upstream"
git config --global --replace-all alias.rh "reset --hard"
git config --global --replace-all alias.mt "mergetool"
git config --global --replace-all core.editor "nvim"
git config --global --replace-all push.default "tracking"
git config --global --replace-all alias.l "log --oneline --graph"
git config --global --replace-all pull.rebase true
git config --global --replace-all init.defaultBranch main

# script_install deno "curl -fsSL https://deno.land/x/install/install.sh | $SHELL"
#script_install pyenv "curl https://pyenv.run | $SHELL"
# script_install fzf "git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install --completion --key-bindings --update-rc"
# script_install lvim "$SHELL <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh) --no-install-dependencies && sudo ln -s ~/.local/bin/lvim /usr/bin/lvim"
# script_install rustc "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | $SHELL"
# script_install bun "curl -fsSL https://bun.sh/install | $SHELL"

install fastfetch
script_install opencode "curl -fsSL https://opencode.ai/install | bash"

# Configure alacritty
$SHELL ~/dotfiles/configs/alacritty.sh

# Configure neovim keymaps
mkdir -p ~/.config/nvim/lua/config
cp ~/dotfiles/configs/keymaps.lua ~/.config/nvim/lua/config/keymaps.lua

# # not using OMZSH
# if [ -d "$HOME/.oh-my-zsh" ] && [ -f "$HOME/.zshrc" ]; then
#     print_exists "Oh My Zsh"
# else
#     print_needs "Oh My Zsh"
#   sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
# fi

# backup .zshrc
if [ "$SHELL" = "/bin/zsh" ] || [ "$SHELL" = "/usr/bin/zsh" ]; then
  cp ~/.zshrc ~/.zshrc.backup
  # replace theme
  awk '/ZSH_THEME=/ {sub(/=.*/, "=\"pmcgee\"")} 1' ~/.zshrc >temp.zshrc && mv temp.zshrc ~/.zshrc
else
  cp ~/.bashrc ~/.bashrc.backup
fi

# projets's dev folder
{
  mkdir ~/dev >/dev/null 2>&1 && echo -e "${WARN}create ${NORM}~/dev folder"
} || {
  echo -e "${PASS}found ${NORM}~/dev folder"
}

