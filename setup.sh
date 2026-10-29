#!/usr/bin/env bash
. ~/dotfiles/utils.sh

echo "Will install using $SHELL ($0)"

# run the correct setup file
unameOut="$(uname -s)"
case "${unameOut}" in
Linux*)
  # Check for Arch Linux first
  if [[ -f /etc/arch-release ]] || command -v pacman &>/dev/null; then
    OS_DIR=variants/archlinux
  else
    # Other Linux (Ubuntu, Fedora, …): the shared profile alone, no OS variant.
    OS_DIR=""
  fi
  ;;
Darwin*) OS_DIR=variants/osx ;;
*) echo "No setup for this OS (${unameOut})" ;;
esac

# Check for Termux environment
if [[ -n "$TERMUX_VERSION" ]] || [[ "$PREFIX" == *"com.termux"* ]]; then
  OS_DIR=variants/termux
fi

install_profile "shared"

# An OS profile only runs when one exists for the detected environment; on any
# other Linux the shared profile is the whole setup (the old debian/ubuntu
# variants were dropped -- their tools moved to mise).
if [[ -n "$OS_DIR" ]]; then
  # Extract just the variant name from the OS_DIR path
  install_profile "$(basename "$OS_DIR")"
else
  echo -e "${WARN}no OS-specific profile; shared profile only${NORM}"
fi

# Install the Framework Desktop RGB monitor as the privileged
# framework-rgb@<user> system daemon.
if [[ "$unameOut" == Linux* ]]; then
  "$SHELL" "$DOT_DIR/framework-ryzen/setup.sh"
fi

# Omarchy is an Arch overlay with setup-only configuration (no shell profile).
# Apply it after the Arch profile so Hyprland overrides, including the numpad
# workspace bindings, are stowed after the base OS configuration.
if [[ "$(basename "$OS_DIR")" == "archlinux" ]] && command -v omarchy &>/dev/null; then
  echo -e "${INFO}applying ${NORM}omarchy configuration..."
  "$SHELL" "$DOT_DIR/variants/omarchy/setup.sh"
fi

# Prune stale profiles/hooks only now, so aliases stay available during the update.
clean_imports

echo "All done!"
