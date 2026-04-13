#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

if [ -d "$HOME/.oh-my-zsh" ]; then
  echo "ohmyzsh is already installed"
else
  echo "installing ohmyzsh..."
  yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  source ~/.zshrc
fi

if needs brew; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install tiles
[[ -d /Applications/Tiles.app ]] || brew install tiles

if needs nvim; then
  brew tap homebrew/cask-fonts
  brew install --cask font-victor-mono-nerd-font
  brew install --HEAD neovim
fi

if needs colima; then
  brew install colima
fi

# arg 1 is the brew namespace, arg 2 is the Application namespace
function force_install {
  if needs "$1"; then
    install "$1" &&
      xattr -d com.apple.quarantine /Applications/$2.app || echo "$2 already autorized"
  fi
}

force_install aerospace Aerospace
force_install alacritty Alacritty
force_install chromium Chromium

stow_link claude
stow_link zellij
stow_link aerospace
stow_link alacritty
stow_link alacritty-osx
stow_link nvim

# Generate alacritty os.toml with correct zellij path for current architecture
# (stow puts a symlink, but we need the actual binary path which differs between Intel and Apple Silicon)
ZELLIJ_PATH=$(which zellij 2>/dev/null || echo "${HOMEBREW_PREFIX:-/usr/local}/bin/zellij")
rm -f ~/.config/alacritty/os.toml
cat > ~/.config/alacritty/os.toml << EOF
[terminal.shell]
program = "$ZELLIJ_PATH"
args = ["attach", "--create", "1"]
EOF

# call `defaults delete <property>` to reset to default
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
defaults write -g QLPanelAnimationDuration -float 0
defaults write com.apple.dock launchanim -bool false
defaults write com.apple.finder DisableAllAnimations -bool true
defaults write com.apple.dock springboard-show-duration -float .1
defaults write com.apple.dock springboard-hide-duration -float .1
defaults write com.apple.dock expose-animation-duration -float 0.1
# Allows grab windows with Ctrl+CMD
defaults write -g NSWindowShouldDragOnGesture -bool true
