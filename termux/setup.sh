#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

echo "Setting up Termux environment..."

# Update package lists
pkg update -y

# Core development tools
install git
install curl
install wget
install tree
script_install rg "pkg install -y ripgrep"
install fzf
install jq
install htop
install zellij
install zsh
install fish

# Programming languages and tools
install python
script_install golang "pkg install -y golang"

# Text editors
install neovim

# Terminal multiplexers and tools
exists zellij || pkg install -y zellij

# GitHub CLI
install gh

# Development utilities
install make
install cmake
install clang
install pkg-config

# Android-specific packages (check if already available)
exists termux-setup-storage || install termux-api
exists termux-info || install termux-tools

# Set up storage access (only if not already set up)
if [ ! -d ~/storage ]; then
    echo "Setting up storage access..."
    termux-setup-storage
else
    echo "Storage access already configured"
fi

# Set default shell to zsh if available (Termux doesn't have chsh)
if command -v zsh >/dev/null 2>&1; then
    if [ "$SHELL" != "$(which zsh)" ]; then
        echo "To set zsh as default shell, add this to your ~/.bashrc:"
        echo "exec zsh"
    fi
fi

echo "Termux setup complete!"
echo "Don't forget to:"
echo "1. Install Termux:API app from F-Droid for enhanced functionality"
echo "2. Grant storage permissions when prompted"
echo "3. Restart your terminal session"
