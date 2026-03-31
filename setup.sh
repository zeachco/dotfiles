#!/usr/bin/env bash
. ~/dotfiles/utils.sh

clean_imports

echo "Will install using $SHELL ($0)"

# run the correct setup file
unameOut="$(uname -s)"
case "${unameOut}" in
Linux*)
  # Check for Arch Linux first
  if [[ -f /etc/arch-release ]] || command -v pacman &>/dev/null; then
    OS_DIR=variants/archlinux
  else
    OS_DIR=variants/debian
  fi
  ;;
Darwin*) OS_DIR=variants/osx ;;
*) echo "No setup for this OS (${unameOut})" ;;
esac

# Check for Termux environment
if [[ -n "$TERMUX_VERSION" ]] || [[ "$PREFIX" == *"com.termux"* ]]; then
  OS_DIR=variants/termux
elif [[ "$(lsb_release -a 2>/dev/null)" =~ "Ubuntu" ]]; then
  OS_DIR=variants/ubuntu
fi

install_profile "common"

# note: the debian profile is also adapted to arch/manjaroo
install_profile "$OS_DIR"

echo "All done!"
