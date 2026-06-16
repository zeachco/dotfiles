# Prerequisites

To use this dotfiles setup, you need to be able to get the repository onto your machine. You have several options:

1. **Best**: Use GitHub CLI (`gh`) with authentication
2. **Good**: Use `git clone` with SSH or HTTPS
3. **Fallback**: Download the ZIP file from [GitHub](https://github.com/zeachco/dotfiles) and extract it to `~/dotfiles`

The setup script will install git and other missing tools if needed.

# Installation

## Clone and run

### With GitHub CLI (recommended)

```sh
gh repo clone zeachco/dotfiles ~/dotfiles && bash ~/dotfiles/setup.sh
```

### With git clone

```sh
git clone git@github.com:zeachco/dotfiles.git ~/dotfiles && bash ~/dotfiles/setup.sh
```

### Without git (fallback)

Download the [repository ZIP](https://github.com/zeachco/dotfiles/archive/refs/heads/main.zip), extract it to `~/dotfiles`, then run:

```sh
bash ~/dotfiles/setup.sh
```

## Update setup

you can just run `dotfiles_update` and it will reapply all changes and remove deprecated configs if any

# Ubuntu special case

For ubuntu, it also installs [omakub](https://omakub.org/) it's just too good to ignore, other OS manually installs the good parts of omakub that I want there like zellij, nvim, sh utils configs

# Supports

- linux debian/arch based (with apt-get such as Ubuntu)
- linux debian/arch based (with pacman such as Manjaroo)
- maxos (with xcode)
- spin cloud debian-based server
- extensible by profile

# Includes

## How this repo works

The repository uses a profile-based approach for different environments. When you run `setup.sh`:
1. It automatically detects your operating system and environment (macOS, Arch, Debian, Ubuntu, Termux, etc.).
2. It first runs the `common` profile which installs the base set of tools and configurations using `stow` for symlinking `configs/` into your `$HOME`.
3. It then runs the specific profile for your OS (e.g. `variants/osx`, `variants/ubuntu`).
4. Profiles use a helper script (`utils.sh`) to intelligently manage dependencies across OS package managers (apt, pacman, brew, pkg).
5. It safely injects a source hook into your shell's initialization file (`~/.bashrc`, `~/.zshrc`, etc.) to load aliases, variables, and bash functions from `.dotfiles_<variant>`.
6. You can re-run the setup at any time safely to update or apply new configs.

## Programing languages

Uses [mise](https://mise.jdx.dev/) and [devbox](https://www.jetify.com/devbox) to control all envs for python, node, rust, go, etc...

## Tools

- git config (auto config with email / name / rebase merge mode and vim editor)
- git aliases (ie `gco` and `git co` for git checkout) git aliases print the real command
- lunarvim (text editor)
- neovim (text editor)
- ligature nerd fonts
- fzf (fast file searching)
- zellij (terminal multiplexer with session and workspace management)
- g++ compiler

## bash functions

- ipp - public ip print
- ipl - local ip print
