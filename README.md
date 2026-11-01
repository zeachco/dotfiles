# dotfiles

Highly opinionated personal setup. It installs and configures the tools **I** use, the way I
use them. Expect it to overwrite shell init hooks, symlink configs into `$HOME`, and install
packages without asking. Fork it if you want something else.

## Install

```sh
gh repo clone zeachco/dotfiles ~/dotfiles && bash ~/dotfiles/setup.sh
```

`git clone git@github.com:zeachco/dotfiles.git` works too. Without git (fresh
install), fetch the [ZIP](https://github.com/zeachco/dotfiles/archive/refs/heads/main.zip);
setup.sh installs git and turns the folder into a clone:

```sh
curl -fsSL https://github.com/zeachco/dotfiles/archive/refs/heads/main.zip -o /tmp/dotfiles.zip \
  && unzip -q /tmp/dotfiles.zip -d /tmp && mv /tmp/dotfiles-main ~/dotfiles && bash ~/dotfiles/setup.sh
```

On NixOS, where curl/unzip may not be on PATH yet, prefix with
`nix-shell -p curl unzip --run '...'`.
Re-run with `dotfiles_update` to apply changes and remove deprecated configs.

## Platforms

| Platform                        | Coverage                                    |
| ------------------------------- | ------------------------------------------- |
| Arch-based Linux (pacman)       | full, including Omarchy/Hyprland integration |
| NixOS (nix profile + module)    | shared tools + `variants/nixos/dotfiles.nix` for root-level state |
| macOS (with Xcode tools)        | full                                        |
| Termux (Android)                | shared profile only                         |
| Other Linux                     | shared profile only; add `variants/<os>/`   |

## What it covers

- **Shell**: zsh/bash profile, aliases, functions (`ipp`, `ipl`, …), source hook into your rc file
- **Editor and terminal**: neovim, alacritty, tmux (Omarchy keybindings on Linux and macOS), nerd fonts, fzf
- **Git**: identity, rebase-first config, aliases that echo the real command
- **Languages**: [mise](https://mise.jdx.dev/) and [devbox](https://www.jetify.com/devbox) for node, python, rust, go, …
- **AI agents**: shared skills and configs for Claude Code, Codex, opencode, pi, and herdr
- **Local LLMs**: llama.cpp model serving (launchd on macOS, systemd on Arch) — see `llamacpp/`
- **Themes**: per-app themes switched with `bin/theme-switch`
- **Framework Desktop**: Rust RGB dashboard daemon — see `framework-ryzen/`

## How it works

`setup.sh` detects the OS, runs the `shared` profile (Stow-symlinks `configs/` into `$HOME`),
then the OS profile in `variants/<os>/`. Details in
**[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**; agent guidance in **[AGENTS.md](AGENTS.md)**.
