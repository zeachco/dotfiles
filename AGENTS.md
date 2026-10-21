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
| `skills/`           | Agent skills shared by every harness (Claude Code, Codex, opencode, pi), one dir per skill; each `configs/<harness>` package links it in |
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
- **Harness skill dirs are real directories, linked one skill at a time.** `unfold_dir`
  (utils.sh) creates `~/.claude/skills`, `~/.codex/skills`, `~/.pi/agent/skills` and
  `~/.config/opencode/skills` before their package is stowed, so Stow links each entry of
  `skills/` on its own instead of folding the whole directory (or the whole `~/.claude`) into
  the repo. Claude Code's `.trash/`/`synced/`, Codex's `.system/`, omarchy's skill links and
  per-box installs like `use-railway` stay in `$HOME`. A new skill reaches a machine on the
  next `dotfiles_update`.
- **Claude Code's settings.json is stowed through a clean filter.** `theme` (bin/theme-switch)
  and `hooks` (herdr's SessionStart hook, absolute path) are machine state and never reach
  git — a hook added there by hand is not tracked either. On a box whose
  `~/.claude/settings.json` predates the package, the first `stow_link claude` replaces it;
  re-run herdr's Claude integration afterwards to get the hook back.
- **Herdr's server rewrites its own config.** `~/.config/herdr/config.toml` is Stow-linked on
  macOS, but the server patches it in place (onboarding state, channel) and `herdr update`
  regenerates it wholesale, so the live file is git-ignored and seeded by setup from
  `configs/herdr/config.seed.toml` (only when absent); `bin/herdr-config` patches keys
  through the symlink — never retemplate the file. The keymap has one source for every
  platform, `configs/herdr/keys.toml`: `herdr-config ensure-keys` copies its `[keys]` table
  into the live config (re-run it after `herdr update`, which drops the table and leaves the
  prefix on ctrl+b). Hand-maintained changes go in the seed. Alt chords need `option_as_alt`
  (alacritty-osx) and CSI-u Enter bindings (alacritty, foot). Validate with `herdr config check`.
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
