#!/bin/env bash
source ~/dotfiles/utils.sh

if [ $(command -v neofetch) ] ; then
    echo "neofetch already installed"
else
    echo "Installing neofetch"
    brew install neofetch
fi

FONT=VictorMono

brew tap homebrew/cask-fonts &&
brew install --cask font-$FONT-nerd-font

_add_zsh_variant osx
