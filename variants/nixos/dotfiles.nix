# System-level half of the NixOS variant. Imported from /etc/nixos/configuration.nix
# through the /etc/nixos/dotfiles.nix link that variants/nixos/setup.sh creates:
#
#   imports = [ ./hardware-configuration.nix ./dotfiles.nix ];
#
# Or, before anything is cloned (no git on the box yet), straight from GitHub;
# nixos-rebuild then provides git for the clone + setup.sh that follow:
#
#   "${builtins.fetchTarball "https://github.com/zeachco/dotfiles/archive/main.tar.gz"}/variants/nixos/dotfiles.nix"
#
# Everything a user can install on their own goes through `nix profile` in
# variants/nixos/setup.sh instead, so this file only holds what needs root:
# the login shell, fonts, system packages the stowed configs expect, and services.
{ config, pkgs, lib, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Keep the store from growing without bound; `nixgc` does it on demand.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  nixpkgs.config.allowUnfree = true;

  # Zsh as the login shell: the shared profile's zsh-vi-mode check and the
  # tmux-attaching alacritty os.toml both assume it.
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  # Only what the bootstrap and the GUI need; every CLI tool is owned by the
  # user profile (setup.sh) so it is not installed twice.
  environment.systemPackages = with pkgs; [
    stow
    git
    curl
    alacritty
    # llama.cpp Vulkan build deps -- see variants/archlinux/setup.sh for why
    # they are pinned here rather than left to drift.
    vulkan-headers
    vulkan-loader
    vulkan-tools
    spirv-headers
    shaderc
  ];

  # Alacritty's look.toml asks for JetBrainsMono Nerd Font.
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.victor-mono
  ];

  # mDNS: avahi-browse is used by the streaming helpers (Chromecast discovery).
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };

  # Flatpak is installed by setup.sh into the user profile, but the portal and
  # the system service are root-level.
  services.flatpak.enable = true;
  xdg.portal.enable = true;

  # PipeWire + WirePlumber, so the stowed wireplumber config applies.
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
}
