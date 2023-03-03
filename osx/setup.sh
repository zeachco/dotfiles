#!/bin/env bash
source ~/dotfiles/utils.sh

brew install neofetch

_add_zsh_variant osx

FONT=VictorMono

brew tap homebrew/cask-fonts &&
brew install --cask font-$FONT-nerd-font
