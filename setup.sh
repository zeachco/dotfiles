#!/bin/env sh
. ~/dotfiles/utils.sh

clean_imports

echo "Will install using $SHELL ($0)"

# run the correct setup file
unameOut="$(uname -s)"
case "${unameOut}" in
Linux*) OS_DIR=debian ;;
Darwin*) OS_DIR=osx ;;
*) echo "No setup for this OS (${unameOut})" ;;
esac

# Check for Termux environment
if [[ -n "$TERMUX_VERSION" ]] || [[ "$PREFIX" == *"com.termux"* ]]; then
  OS_DIR=termux
elif [[ "$(lsb_release -a 2>/dev/null)" =~ "Ubuntu" ]]; then
  OS_DIR=ubuntu
fi

install_profile "common"

# note: the debian profile is also adapted to arch/manjaroo
install_profile "$OS_DIR"
