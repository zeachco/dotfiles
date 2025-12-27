#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

# install ohmyzsh
yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

souce ~/.zshrc

if needs brew; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi


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
  install $1 && \
  xattr -d com.apple.quarantine /Applications/$2.app || echo "$2 already autorized"
}

force_install aerospace Aerospace
force_install alacritty Alacritty
force_install chromium Chromium

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

