#!/usr/bin/env bash
. ~/dotfiles/utils.sh

clean_imports

# Clean up old dotfiles_* files before installing profiles
for old_file in $HOME/.dotfiles_*; do
    if [[ -f "$old_file" ]]; then
        echo -e "${WARN}removing old ${NORM}$old_file"
        rm -f "$old_file"
    fi
done

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

install_profile "shared"

# note: the debian profile is also adapted to arch/manjaroo
# Extract just the variant name from the OS_DIR path
install_profile "$(basename $OS_DIR)"

echo "All done!"
