#!/bin/bash
source ~/dotfiles/utils.sh

if needs neofetch; then
    brew install neofetch
fi

if needs neovim; then
    brew tap homebrew/cask-fonts 
    brew install --cask font-victor-mono-nerd-font
    brew install --HEAD neovim
fi