#!/bin/bash

# run the correct setup file
unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     SETUP_DIR=debian;;
    Darwin*)    SETUP_DIR=osx;;
    # CYGWIN*)    SETUP_DIR=Cygwin;;
    # MINGW*)     SETUP_DIR=MinGw;;
    *)          echo "No setup for this OS (${unameOut})"
esac

echo "Installing common dependencies..." 
bash ./common/setup.sh
echo "done."
echo "Installing $SETUP_DIR dependencies..."
eval "bash ./$SETUP_DIR/setup.sh"
echo "done."
