#!/bin/sh

# Source utils.sh for shared functions
source "$HOME/dotfiles/utils.sh"

# --- NixOS: system (declarative) vs user profile (imperative) --------------------
# `nixup` rebuilds the system from /etc/nixos (which imports
# ~/dotfiles/variants/nixos/dotfiles.nix); `nixin`/`nixrm` act on the user's
# `nix profile`, the layer the shared `install` helper targets.

nixup() {
    echo -e "${WARN}rebuilding system from /etc/nixos...${NORM}"
    sudo nixos-rebuild switch "$@"
}

nixupgrade() {
    echo -e "${WARN}updating channels and rebuilding...${NORM}"
    sudo nixos-rebuild switch --upgrade "$@"
}

nixin() {
    for pkg in "$@"; do
        echo -e "${WARN}installing ${NORM}$pkg into the user profile..."
        nix_profile_install "$pkg"
    done
}

nixrm() {
    for pkg in "$@"; do
        echo -e "${WARN}removing ${NORM}$pkg from the user profile..."
        nix profile remove "$pkg"
    done
}

nixss() {
    nix search nixpkgs "$1"
}

nixls() {
    nix profile list
}

nixgen() {
    echo -e "${INFO}system generations:${NORM}"
    sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
}

nixrollback() {
    echo -e "${WARN}rolling back to the previous system generation...${NORM}"
    sudo nixos-rebuild switch --rollback
}

nixgc() {
    echo -e "${WARN}collecting garbage (user + system) ...${NORM}"
    nix-collect-garbage -d
    sudo nix-collect-garbage -d
}

# Try a package without installing it: `nixsh ripgrep fd` opens a shell with both.
nixsh() {
    args=()
    for pkg in "$@"; do args+=("nixpkgs#$pkg"); done
    nix shell "${args[@]}"
}

# Run a command from a package once: `nixrun cowsay hi`
nixrun() {
    pkg="$1"; shift
    nix run "nixpkgs#$pkg" -- "$@"
}

# Which store path provides a binary on PATH.
nixown() {
    [[ -z "$1" ]] && { echo -e "${FAIL}usage: nixown <command>${NORM}"; return 1; }
    readlink -f "$(command -v "$1")"
}

# System maintenance
alias journalctl-errors='journalctl -p 3 -xb'
alias systemctl-list='systemctl list-units --type=service --state=running'

sysinfo() {
    echo -e "${INFO}=== System Information ===${NORM}"
    echo "NixOS: $(nixos-version)"
    echo "Kernel: $(uname -r)"
    echo "Uptime: $(uptime -p)"
    echo "User profile packages: $(nix profile list 2>/dev/null | grep -c '^Name:')"
    echo "Disk usage:"
    df -h / | tail -1
    echo "Nix store:"
    du -sh /nix/store 2>/dev/null | cut -f1
    echo "Memory usage:"
    free -h | grep "^Mem:"
}

# Interactive installer: search nixpkgs, pick with fzf, install into the profile.
nixi() {
    if ! command -v fzf &>/dev/null; then
        echo -e "${FAIL}fzf not installed${NORM}. Install with: nixin fzf"
        return 1
    fi
    [[ -z "$1" ]] && { echo -e "${FAIL}usage: nixi <search term>${NORM}"; return 1; }
    package="$(
        nix search nixpkgs "$1" --json 2>/dev/null |
        jq -r 'to_entries[] | "\(.key | sub("^legacyPackages\\.[^.]+\\."; ""))\t\(.value.description)"' |
        fzf -m --prompt="Select packages to install: " --with-nth=1,2 -d '\t' |
        cut -f1 | tr "\n" " "
    )"
    [[ $package ]] && read -n1 -p "Install ${package}? [y/N]: " install
    [[ "$install" == "y" ]] && nixin $package
}

# zsh-vi-mode is installed into the user profile by the shared setup; nothing on
# NixOS sources it automatically (no /usr/share), so do it here.
ZVM="$HOME/.nix-profile/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh"
[[ -n "$ZSH_VERSION" && -f "$ZVM" ]] && source "$ZVM"

# Same two-router layout as archlinux: the cheap tier serves the shell helpers so
# a tab rename can never evict the big model from the light router. See the
# archlinux profile for the LRU reasoning.
export AI_LLAMA_URL="http://127.0.0.1:7071"
