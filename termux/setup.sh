#!/bin/env sh
. ~/dotfiles/utils.sh

echo "Setting up Termux environment..."

# Update package lists
pkg update -y

# Core development tools
install git
install curl
install wget
install tree
install ripgrep rg
install fzf
install jq
install htop
install tmux
install zsh
install fish

# Programming languages and tools
install nodejs
install python
install golang go
install rust
install bun

# Text editors (nvim already installed via LazyVim)
exists nvim

# Terminal multiplexers and tools
exists zellij || pkg install -y zellij

# GitHub CLI
install gh

# Development utilities
install make
install cmake
install clang
install pkg-config

# Android-specific packages
install termux-api
install termux-tools

# Optional: neofetch for system info
install neofetch

# Set up storage access
if [ ! -d ~/storage ]; then
    echo "Setting up storage access..."
    termux-setup-storage
fi

# Set default shell to zsh if available
if command -v zsh >/dev/null 2>&1; then
    if [ "$SHELL" != "$(which zsh)" ]; then
        echo "Changing default shell to zsh..."
        chsh -s $(which zsh)
    fi
fi

echo "Termux setup complete!"
echo "Don't forget to:"
echo "1. Install Termux:API app from F-Droid for enhanced functionality"
echo "2. Grant storage permissions when prompted"
echo "3. Restart your terminal session"