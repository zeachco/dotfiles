#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

# NixOS splits in two: user-level packages go through `nix profile` (so the
# shared `install`/`install_pkg` calls work unchanged), while anything that
# needs root -- login shell, fonts, system services, Vulkan -- is declarative in
# variants/nixos/dotfiles.nix, imported from /etc/nixos/configuration.nix.

# `nix profile` is a flakes/nix-command feature; enable it per user so the
# shared profile can install into the profile without touching /etc/nix.
NIX_CONF="$HOME/.config/nix/nix.conf"
if ! grep -qs 'experimental-features.*nix-command' "$NIX_CONF"; then
  echo -e "${WARN}enabling ${NORM}nix-command + flakes in $NIX_CONF"
  mkdir -p "$(dirname "$NIX_CONF")"
  echo "experimental-features = nix-command flakes" >>"$NIX_CONF"
else
  print_exists "nix-command + flakes"
fi

# Expose the module to the system config. /etc/nixos is root-owned, so the
# link is made once with sudo and the import is left to the user: rewriting
# configuration.nix from a dotfiles script is the one thing nobody wants.
MODULE_LINK=/etc/nixos/dotfiles.nix
if [[ -L "$MODULE_LINK" && "$(readlink "$MODULE_LINK")" == "$DOT_DIR/variants/nixos/dotfiles.nix" ]]; then
  print_exists "$MODULE_LINK"
elif [[ -d /etc/nixos ]]; then
  echo -e "${WARN}linking ${NORM}$MODULE_LINK -> variants/nixos/dotfiles.nix"
  sudo ln -sfn "$DOT_DIR/variants/nixos/dotfiles.nix" "$MODULE_LINK"
fi
if ! grep -qs 'dotfiles.nix' /etc/nixos/configuration.nix; then
  echo -e "${WARN}add ${NORM}./dotfiles.nix to the imports of /etc/nixos/configuration.nix, then: sudo nixos-rebuild switch"
fi

# User-level tools (same set as archlinux, minus what dotfiles.nix provides).
install alacritty
install unzip
install curl
install gcc
install make gnumake # nixpkgs attribute is gnumake
install cmake
install zsh
install s-tui
install nvtop
install btop
install flatpak
install fd
install fzf
install bat
install starship
install bw bitwarden-cli
install avahi-browse avahi
install cvlc vlc

# Check neovim version and install/update if needed
neovimVersion=$(nvim --version 2>/dev/null | head -n 1 | awk '{print $2}' || echo "0.0.0")
if [ "$(echo "${neovimVersion} v0.8" | tr " " "\n" | sort -V | tail -n 1)" = "${neovimVersion}" ]; then
  print_exists "neovim $neovimVersion"
else
  print_needs "neovim 0.8+"
  install nvim neovim
fi

stow_link wireplumber
stow_link alacritty
stow_link alacritty-archlinux # same tmux-attaching os.toml as on Arch
stow_link nvim
unfold_dir "$HOME/.config/opencode/skills"
stow_link opencode

echo -e "${PASS}NixOS setup complete!${NORM}"
