#!/bin/env sh
source ~/dotfiles/utils.sh

clean_imports

echo "Will install using $SHELL ($0)"

# run the correct setup file
unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     OS_DIR=debian;;
    Darwin*)    OS_DIR=osx;;
    *)          echo "No setup for this OS (${unameOut})"
esac

install_profile "common"

# note: the debian profile is also adapted to arch/manjaroo
install_profile "$OS_DIR"
