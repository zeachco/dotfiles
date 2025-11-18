#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

install rg # ripgrep
install fd # fast find

if needs nvim; then
  brew tap homebrew/cask-fonts
  brew install --cask font-victor-mono-nerd-font
  brew install --HEAD neovim
fi

if needs colima; then
  brew install colima
fi

# call `defaults delete <property>` to reset to default
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
defaults write -g QLPanelAnimationDuration -float 0
defaults write com.apple.dock launchanim -bool false
defaults write com.apple.finder DisableAllAnimations -bool true
defaults write com.apple.dock springboard-show-duration -float .1
defaults write com.apple.dock springboard-hide-duration -float .1
defaults write com.apple.dock expose-animation-duration -float 0.1
