#!/bin/env bash
source ~/dotfiles/utils.sh

clean_imports

# run the correct setup file
unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     OS_DIR=debian;;
    Darwin*)    OS_DIR=osx;;
    *)          echo "No setup for this OS (${unameOut})"
esac

install_profile "common"

# instead of OS based, let's just run the spin profile for machines using spin
FILE=/opt/spin
if test -d "$FILE"; then
    install_profile "spin"
fi

install_profile "$OS_DIR"