#!/bin/env bash
source ~/dotfiles/utils.sh

# run the correct setup file
unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     SETUP_DIR=debian;;
    Darwin*)    SETUP_DIR=osx;;
    *)          echo "No setup for this OS (${unameOut})"
esac

echo "Installing common dependencies..." 
zsh "$DOT_DIR/common/setup.sh"
echo "done."

# instead of OS based, let's just run the spin profile for remote spin instances
if [[ ${SPIN} ]]; then
	SETUP_DIR=spin
fi

echo "Installing $SETUP_DIR dependencies..."
zsh "$DOT_DIR/$SETUP_DIR/setup.sh"
echo "done."