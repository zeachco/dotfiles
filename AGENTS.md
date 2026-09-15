# AI Agent Guide: Dotfiles Architecture

Cross-platform dotfiles using two-tier profiles (shared base + OS-specific overrides) and GNU Stow for config symlinks.

## Flow: setup.sh → OS detection → install_profile("shared") → install_profile(OS_variant)

**Core files**: `setup.sh` (orchestrator), `utils.sh` (install/stow_link/install_profile), `variants/*/setup.sh` (packages), `variants/*/profile.sh` (shell config)

## OS Detection (setup.sh:17-36)

Linux → /etc/arch-release or pacman → archlinux | else → debian  
Overrides: $TERMUX_VERSION → termux | lsb_release=Ubuntu → ubuntu  
Darwin → osx

## Variants (variants/*)

**Inheritance**: shared sourced FIRST → OS-specific (allows function shadowing)

| Variant   | PM         | Stow Configs                        | Notes                                        |
| --------- | ---------- | ----------------------------------- | -------------------------------------------- |
| shared    | agnostic   | alacritty, tmux, pi                 | Base: git, rg, fd, gh, fzf, tmux, pi         |
| debian    | apt        | claude, alacritty-debian, nvim      | Core tools                                   |
| ubuntu    | apt        | Same as debian                      | + devbox, shortcuts.sh (GNOME keys)          |
| osx       | brew       | 6 pkgs (aerospace, sketchybar, herdr) | Generates herdr os.toml, option_as_alt     |
| archlinux | pacman+yay | wireplumber                         | AUR helper, 20+ pac*/yay* functions          |
| termux    | pkg        | None                                | Android-specific, redefined killport/network |
| omarchy   | pacman     | hypr, foot, alacritty-omarchy       | Setup-only, modifies Hypr bindings           |

## Stow System (configs/ → ~/)

16 packages mirror home structure: `configs/nvim/.config/nvim/`, `configs/alacritty/.config/alacritty/`  
**stow_link()** (utils.sh:124-148): auto-removes conflicts, uses --restow fallback  
**Override pattern**: base (alacritty, tmux) + OS variants (alacritty-osx, alacritty-omarchy)

## install_profile() (utils.sh:29-44)

1. Run variants/$variant/setup.sh
2. Copy profile.sh → ~/.dotfiles_$variant
3. Source in shell: `[[ -f ~/.dotfiles_$variant ]] && source ~/.dotfiles_$variant # zeachco-dotfiles`

**clean_imports()**: strips old `# zeachco-dotfiles` lines before reinstall

## Key Functions (variants/shared/profile.sh)

**clone [repo]**: GitHub shorthand | **killport [port]**: kill process | **check_for_devbox()**: auto-enters devbox shell  
**Git**: gco, gs, gd, gci, gp (via `_set` - prints before exec) | **\_worktrees.sh**: jira_claude, Herdr integration  
**OS-specific**: archlinux (pacup, yayin), osx (docker wrapper, dark mode), termux (battery, notify)

## Keybindings

`configs/tmux/.config/tmux/tmux.conf` is a copy of Omarchy's tmux config; `bin/herdr-config ensure-keys` mirrors that keymap into `~/.config/herdr/config.toml` (Stow-linked from `configs/herdr` on macOS only; patched key-by-key in place because Herdr's server writes to the same file).
Alt chords need `option_as_alt` on macOS (configs/alacritty-osx) and CSI-u Enter bindings (configs/alacritty, configs/foot). Validate with `herdr config check`.

## Herdr plugins

`herdr plugin install <owner/repo>`; installed globally under `~/.config/herdr/plugins`, so nothing to Stow. None installed right now (`jakekroon/herdr-pr-tracker` was removed, along with its `prefix+m`/`prefix+i`/`prefix+shift+i` bindings and the `$pr` sidebar row override in configs/herdr).

Plugin commands and `[[keys.command]]` entries are spawned by the Herdr **server**, which inherits its environment from whatever launched it -- Alacritty from launchd, i.e. `PATH=/usr/bin:/bin:/usr/sbin:/sbin`. variants/osx/setup.sh therefore launches Herdr through `$SHELL -l -i -c`; without that, anything outside those four directories fails to spawn and only `herdr plugin log` says why (`No such file or directory (os error 2)`). `-i` is load-bearing: zsh reads `~/.zshrc` only when interactive, and that is where the PATH exports live, so a plain `-l -c` still resolves `gh` and brew (path_helper supplies `/opt/homebrew/bin`) while `bun` alone fails. Pane shells never saw this -- they are interactive login shells already. A PATH change reaches the server only when **Alacritty** is relaunched; stopping the server alone respawns it from the client's stale environment.

## Testing

`bash ~/dotfiles/setup.sh` (full) | `dotfiles_update` (remote pull) | `source ~/.zshrc` (reload)

## Neovim: `.git`/`.github` visibility

Handled by `configs/nvim/.config/nvim/lua/plugins/git-visibility.lua` (Telescope `hidden=true`
+ Neo-tree `always_show`). Edit that file, not AGENTS.md.
