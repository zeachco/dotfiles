# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a cross-platform dotfiles repository that provides automated environment setup for multiple operating systems (Linux Debian/Arch, macOS, Ubuntu, Termux). The architecture is profile-based, where each OS has its own profile directory with setup and configuration scripts.

## Architecture

### Core Components

- **utils.sh**: Central utility library providing installation helpers (`install`, `script_install`), existence checks (`exists`, `needs`), and profile management (`install_profile`, `clean_imports`). The `install_profile` function automatically prefixes variant names with `variants/`.
- **setup.sh**: Main entry point that detects OS and orchestrates profile installation by calling `install_profile` for shared + OS-specific profiles

### Profile System

Each profile directory (variants/shared/, variants/debian/, variants/ubuntu/, variants/osx/, variants/termux/) contains:
- **setup.sh**: Installs packages and tools specific to that environment
- **profile.sh**: Shell functions, aliases, and environment variables sourced at shell startup

Profile loading mechanism:
1. setup.sh detects OS and sets OS_DIR variable
2. Calls `install_profile "shared"` then `install_profile` with the variant name (e.g., "debian", "osx")
3. `install_profile` automatically prefixes the variant name with `variants/` to find the correct directory
4. Each profile's profile.sh is copied to ~/.dotfiles_[variant] and sourced from user's shell config

### Key Features

**Automatic devbox shell activation**: The variants/shared/profile.sh contains a `check_for_devbox()` function that automatically enters devbox shells when cd'ing into directories with devbox.json. This is called on both cd and shell startup.

**Git aliases**: Extensive git aliases defined in both git config (variants/shared/setup.sh:21-41) and shell aliases (variants/shared/profile.sh:38-58). Shell aliases use the `_set` helper which prints the actual command being run.

**Package manager abstraction**: The `install` function in utils.sh:74-97 automatically detects whether to use apt, pacman, or pkg (Termux) based on environment.

## Installation & Testing

### Initial Setup
```bash
# Run the main setup script
bash ~/dotfiles/setup.sh
```

### Testing Changes
After modifying profile.sh or setup.sh files, test by re-running setup:
```bash
bash ~/dotfiles/setup.sh
```

Or update from remote:
```bash
dotfiles_update  # Alias defined in variants/shared/profile.sh:7-14
```

### Manual Profile Reload
To reload shell configuration without re-running setup:
```bash
source ~/.bashrc  # or ~/.zshrc depending on shell
```

## Important Shell Functions & Aliases

Defined in variants/shared/profile.sh:

- **clone [repo/project]**: GitHub shorthand to clone repos (e.g., `clone zeachco/dotfiles`) - implemented in advanced/clone.ts
- **ipp**: Print public IP address
- **ipl**: Print local IP address
- **killport [port]**: Kill process listening on specified port
- **ai [model]**: Start local AI model with ollama (default: tinyllama)
- **check_for_devbox**: Auto-enters devbox shell when devbox.json present

Git shortcuts (print actual command before executing):
- gco, gs, gd, gci, gp, gpp, etc. - see variants/shared/profile.sh:38-58

## OS-Specific Notes

**Ubuntu**: Uses Omakub (https://omakub.org/) as base, only installs additional tools needed. See variants/ubuntu/setup.sh:4

**Debian/Arch**: Skips installation on Spin cloud environments (detected via /opt/spin directory). Uses either apt or pacman based on availability.

**Termux**: Android terminal environment, uses pkg package manager

**macOS**: Uses Homebrew (xcode required)

## Configuration Targets

The setup determines which shell config file to modify based on $SHELL:
- bash: ~/.bashrc (or ~/.bash_profile, ~/.bash_login, ~/.profile in that order)
- zsh: ~/.zshrc

Profiles are sourced via lines like:
```bash
[[ -f ~/.dotfiles_shared ]] && source ~/.dotfiles_shared # zeachco-dotfiles variants/shared
```

## Development Tools

**Editor**: nvim (set as EDITOR and SUDO_EDITOR in variants/shared/profile.sh:3-4)

**Version Management**: Uses mise (https://mise.jdx.dev/) and devbox (https://www.jetify.com/devbox) for managing Python, Node, Rust, Go, etc.

**Git Config**: Auto-configured with:
- Rebase mode for pulls (pull.rebase true)
- main as default branch
- nvim as editor
- Credential caching enabled

## Neovim Configuration Reference

See AGENTS.md for Neovim/LazyVim configurations that AI agents can apply, including making .git and .github directories visible in file explorer and fuzzy finder.
