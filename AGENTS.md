# AI Agent Guide: Dotfiles Architecture

Cross-platform dotfiles using two-tier profiles (shared base + OS-specific overrides) and GNU
Stow for config symlinks.

**Start here, then read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — it documents the key
concepts: the setup flow, OS detection, variants, the Stow system, shell profile inheritance,
package-manager abstraction, utilities, themes, the llama.cpp subsystem, and per-OS service
management. This file keeps only the map and the gotchas.

## Repository map

| Path                | What lives there                                                    |
| ------------------- | ------------------------------------------------------------------- |
| `setup.sh`          | Orchestrator: OS detection → `install_profile shared` → `install_profile <variant>` → extras |
| `utils.sh`          | `install_profile`, `stow_link`, `install`/`install_pkg`, `clean_imports`, theme seeding |
| `variants/`         | One dir per OS (+ shared base): `setup.sh` (packages) + `profile.sh` (shell state), partials in `_*.sh` |
| `configs/`          | Stow packages, mirroring `$HOME`: `configs/nvim/.config/nvim/…` → `~/.config/nvim/…` |
| `llamacpp/`         | Local model serving: shared launchers/menu/fetch lib, osx (launchd) + archlinux (systemd) — see [llamacpp/README.md](llamacpp/README.md) |
| `bin/`              | Helper scripts, invoked by absolute path — see [bin/README.md](bin/README.md) |
| `themes/`           | Per-app themes; `themes/current` is machine state (gitignored)       |
| `framework-ryzen/`  | Rust RGB dashboard for the Framework Desktop, installed as a root systemd daemon |
| `docs/`             | [Architecture](docs/ARCHITECTURE.md) · [Strix Halo LLM runbook](docs/ryzen-llm-setup.md) |
| `todos/`            | Scratch notes, not part of the system                                |

## Gotchas (each one was paid for)

- **`~/.dotfiles_*` are copies, not links.** `install_profile` copies `profile.sh` at install
  time. A profile change reaches a machine only after re-running `setup.sh` /
  `dotfiles_update` — an already-open shell keeps the old values.
- **Stow packages override per file.** Base (alacritty, tmux) + per-OS packages (alacritty-osx,
  alacritty-omarchy); the last stowed package wins. `stow_link` deletes conflicting targets
  first, so never rely on a stale untracked file in `configs/`.
- **Machine-local state is gitignored**: `themes/current`, `configs/alacritty/…/theme.toml`, pi
  `models.json` (seeded from `models.seed.json` **before** stow — without the seed pi comes up
  with no llamacpp providers at all, which sync cannot repair), pi `auth.json`, herdr-agent-state
  files.
- **Herdr's server rewrites its own config.** `~/.config/herdr/config.toml` is Stow-linked on
  macOS, but the server patches it in place (onboarding state, keys), so `bin/herdr-config`
  patches single keys through the symlink — never retemplate the file. Alt chords need
  `option_as_alt` (alacritty-osx) and CSI-u Enter bindings (alacritty, foot). Validate with
  `herdr config check`.
- **The Herdr server inherits a launchd environment on macOS** (Alacritty is started by launchd:
  `PATH=/usr/bin:/bin:/usr/sbin:/sbin`), so plugin commands and `[[keys.command]]` entries can
  only spawn things in those four directories unless the server was started with a real
  environment. `variants/osx/setup.sh` therefore launches Herdr through `$SHELL -l -i -c`
  (`-i` is load-bearing — zsh reads `~/.zshrc` only when interactive, and that is where the PATH
  exports live). A PATH change reaches the server only when **Alacritty** is relaunched; stopping
  the server alone respawns it from the client's stale environment. The only diagnostic is
  `herdr plugin log` (`No such file or directory (os error 2)`).
- **Alacritty live-reload races Stow.** `nudge_alacritty_reload()` (utils.sh) touches the
  alacritty tomls at the end of a variant setup, after the last write — the full rationale is in
  its comment.
- **bash 3.2 on macOS.** Everything under `llamacpp/` that ships to the Mac (fetch lib, hw gate,
  verify) must not use associative arrays, `${var,,}`, mapfile, globstar, or GNU sed/awk.
- **Neovim `.git`/`.github` visibility** is handled by
  `configs/nvim/.config/nvim/lua/plugins/git-visibility.lua` (Telescope `hidden=true` + Neo-tree
  `always_show`). Edit that file, not the docs.

## Testing

`bash ~/dotfiles/setup.sh` (full, idempotent) · `dotfiles_update` (pull + reapply) ·
`source ~/.zshrc` (reload shell state).
