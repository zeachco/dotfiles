#!/bin/bash
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

if [[ "$USER" == "spin" ]]; then
    install_profile "spin"
fi

# note: the debian profile is also adapted to arch/manjaroo
install_profile "$OS_DIR"
