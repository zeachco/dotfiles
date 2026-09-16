# Architecture

The key concepts behind this repo: how it is organized, what each moving part does, and
where the load-bearing decisions live. Machine-specific deep dives:
[ryzen-llm-setup.md](ryzen-llm-setup.md) (Strix Halo local-LLM runbook).

One repo, many machines. `setup.sh` detects the OS and applies two tiers — a **shared base
profile** and an **OS-specific override**. Configs are symlinked with GNU Stow, shell state is
copied and sourced, packages go through a package-manager abstraction. Everything is
idempotent: re-running `setup.sh` (or `dotfiles_update`) **is** the update mechanism.

## Big picture

```
setup.sh
├─ OS detection                    (uname + /etc/arch-release, TERMUX, lsb_release)
├─ clean_imports                   (strip old source hooks from the shell rc)
├─ install_profile "shared"        (base tools + configs on every OS)
├─ install_profile "<variant>"     (osx | debian | ubuntu | archlinux | termux)
├─ framework-ryzen/setup.sh        (Linux only: Framework Desktop RGB daemon)
└─ variants/omarchy/setup.sh       (archlinux only, when `omarchy` is installed)
```

**Core files**: `setup.sh` (orchestrator) · `utils.sh` (`install_profile`, `stow_link`,
`install`, …) · `variants/*/setup.sh` (packages) · `variants/*/profile.sh` (shell state).

## OS detection

`setup.sh` (top of file):

1. `uname` → `Linux` vs `Darwin` (anything else: no setup).
2. Linux: `/etc/arch-release` or a `pacman` binary → **archlinux**, else **debian**.
   The debian profile doubles as the base for Manjaro and friends.
3. Overrides checked afterwards: `$TERMUX_VERSION` / `PREFIX` containing `com.termux` →
   **termux**; `lsb_release` containing Ubuntu → **ubuntu**.
4. `Darwin` → **osx**.

## Variants (`variants/*`)

| Variant     | PM           | Stow configs                       | Notes                                             |
| ----------- | ------------ | ---------------------------------- | ------------------------------------------------- |
| shared      | agnostic     | alacritty, tmux, pi               | Base: git config, rg, fd, gh, fzf, tmux, pi, herdr keymap |
| debian      | apt          | claude, alacritty-debian, nvim    | Core tools                                         |
| ubuntu      | apt          | same as debian                     | + omakub, devbox, GNOME shortcuts                  |
| osx         | brew         | aerospace, sketchybar, herdr, …   | Generates herdr os.toml, `option_as_alt`, launches Herdr via `$SHELL -l -i -c` |
| archlinux   | pacman + yay | wireplumber                        | AUR helpers, `pac*`/`yay*` functions, llama.cpp build sync |
| termux      | pkg          | none                               | Android; redefines `killport`/network helpers     |
| omarchy     | pacman       | hypr, foot, alacritty-omarchy     | Setup-only overlay on archlinux (Hyprland bindings), no shell profile |

**Inheritance**: the shared profile is sourced **first**, then the OS profile, so OS-specific
functions can shadow shared ones (e.g. termux redefines `killport`).

## Stow (`configs/` → `$HOME`)

Each entry in `configs/` is a Stow package that mirrors the home-directory structure:
`configs/nvim/.config/nvim/…` → `~/.config/nvim/…`. `stow_link <pkg>` (utils.sh) does:

1. Installs `stow` itself if missing.
2. Runs `ensure_current_theme` (see Themes) — the nvim colorscheme files are generated from the
   active theme before stow links them.
3. Simulates the stow and **deletes conflicting targets** (files, symlinks, or whole directories
   not owned by stow) so the real stow cannot fail.
4. `stow --target=$HOME <pkg>`, falling back to `--restow` on failure.

**Override pattern**: a base package holds shared config, per-OS packages add/override files —
e.g. `alacritty` (shared window padding) + `alacritty-osx` (Nerd Font family, `option_as_alt`).
The last stowed package wins per file.

**Machine-local state is gitignored, not stowed as tracked content**: `themes/current`,
`configs/alacritty/…/theme.toml`, pi's `models.json` (seeded from `models.seed.json`), pi's
`settings.json` (seeded from `settings.seed.json` — pi rewrites it in place: `defaultModel`,
theme, changelog version) and `models-store.json` (provider-catalog cache, etag/checkedAt),
pi's `auth.json`, and the auto-generated herdr-agent-state files. Anything that differs per
box belongs there — a tracked copy would flip on every sync.

## Shell profiles

`install_profile <variant>` (utils.sh) does **not** link — it **copies**:

1. Runs `variants/<variant>/setup.sh`.
2. Copies `variants/<variant>/profile.sh` → `~/.dotfiles_<variant>`.
3. Appends a marked source hook to the shell rc (`~/.zshrc`, `~/.bashrc`, …):
   `[[ -f ~/.dotfiles_<variant> ]] && source ~/.dotfiles_<variant> # zeachco-dotfiles <variant>`

`clean_imports` strips every `# zeachco-dotfiles` line before re-appending, so repeated runs
never accumulate hooks (it also backs up the rc to `*.backup` first).

**Consequence**: `~/.dotfiles_*` are *copies made at install time*, not live links. A change to
a profile (e.g. a new port in `AI_LLAMA_URL`) reaches you only after re-running `setup.sh` /
`dotfiles_update` — an already-open shell keeps the old values.

`shared/profile.sh` is the workhorse: git aliases via `_set` (print the real command before
executing), `dotfiles_update`, `repos`, `killport`, devbox auto-entry (`ds` /
`check_for_devbox`), one-shot shell init (`DOTFILES_INIT_CMD`), and it sources the partials:

- `variants/shared/_ai_tools.sh` — `summarize`, `tab_autoname` (cheap-tier traffic)
- `variants/shared/_worktrees.sh` — git-worktree + Herdr helpers
- `variants/shared/_streaming.sh` — media streaming helpers
- `llamacpp/shared/_llama.sh` then `llamacpp/shared/_los_menu.sh` — llama.cpp launchers, verbs,
  and the `los` fzf menu (order matters: the menu calls back into the verbs)

## Package managers

`utils.sh` abstracts apt / pacman / brew / pkg (Termux) behind a few functions:

| Function          | Checks presence by                    | Use for                                                        |
| ----------------- | ------------------------------------- | -------------------------------------------------------------- |
| `install <cmd> [pkg]` | `command -v <cmd>`                 | Anything that ships a binary                                   |
| `install_pkg <pkg>`   | the PM's own database (`dpkg-query`, `pacman -Q`, `brew list`) | Headers, libraries, plugins — anything with no binary to probe for |
| `script_install <cmd> <exec>` | `command -v <cmd>`        | Installer scripts (curl \| bash, …)                            |
| `needs` / `exists`    | `command -v`                          | Predicates used by the above                                   |

The split between `install` and `install_pkg` is load-bearing: `command -v vulkan-headers` can
never succeed, so `install` re-ran the package manager on every update until `install_pkg`
existed.

## Utilities (`bin/`)

Standalone helpers, invoked by absolute path from profiles, nvim, and the setup scripts (there
is no PATH entry). Full index with knobs and platform notes: [`bin/README.md`](../bin/README.md).
Mostly: theme switching, Herdr config patching, llama.cpp client sync/audit, and a voice
pipeline (`listen` → `converse` → `say`).

## Themes (`themes/`)

Each theme is a directory of per-app files (alacritty, neovim, herdr, btop, claude, codex,
VS Code). `bin/theme-switch` copies the chosen theme to `themes/current` (gitignored — machine
state) and patches the per-app settings. `ensure_current_theme` (utils.sh) seeds the nvim
`theme-light`/`theme-dark` files from the active theme on every stow, so the nvim colorscheme
follows the theme without manual steps.

## The llama.cpp subsystem (`llamacpp/`)

Local model serving for exactly two machines — an Apple Silicon Mac (Metal) and the Strix Halo
box (Vulkan) — gated by `llamacpp/shared/_hw-gate.sh` so no other host that runs
`dotfiles_update` brew-installs llama.cpp or burns cores on a rebuild.

- **`shared/`** — cross-OS: the foreground launchers (`los-server-light/cheap/heavy`) and
  verbs (`los-load`, `los-drain`) in `_llama.sh`; the `los` fzf menu over all tiers; the
  HuggingFace fetch library + GGUF integrity verification; `clone.sh` (clones `~/dev/llama.cpp`
  and starts initial downloads).
- **`osx/`** — brew install, the router as a launchd *user agent*, the root LaunchDaemon that
  raises Metal's wired-memory cap, `osx.ini` presets, `fetch-models-osx.sh` (opt-in).
- **`archlinux/`** — the router as three systemd *user* units (one per tier), INI presets,
  `fetch-models.sh`, and `update.sh` (keeps the checkout + Vulkan build current on
  `dotfiles_update`, gated to the Strix Halo box).

Tiers and ports, model lifecycle, and client integration: [`llamacpp/README.md`](../llamacpp/README.md).
The Strix Halo machine runbook (GTT unlock, backend choice, incidents, per-model numbers):
[ryzen-llm-setup.md](ryzen-llm-setup.md).

## Per-OS service management

The same "long-running thing" is installed per-platform with the platform's native mechanism:

- **macOS (launchd)**: user agents in `~/Library/LaunchAgents` (Aqua session → they survive
  reboots and come back on GUI login). launchd performs **no variable expansion** — paths are
  baked in at install time. Root sysctl changes need a LaunchDaemon (`iogpu.wired_limit_mb`).
  GUI apps like Alacritty start from launchd with a bare PATH, so anything they spawn (Herdr)
  is launched through `$SHELL -l -i -c` to get the real environment.
- **Arch (systemd `--user`)**: `~/.config/systemd/user/*.service` with `WantedBy=default.target`
  so units return at login. Router units carry `CPUQuota`/`--threads` caps by default.
- **Framework Desktop RGB**: the one *system* (root) daemon, `framework-rgb@<user>.service`,
  installed by `framework-ryzen/install-root.sh`; the Rust source lives in
  `framework-ryzen/framework-rgb/`.

All installers follow the same contract: render the artifact, compare with what is installed
(`cmp -s`), and exit before touching the running service when nothing changed — so a no-op
`dotfiles_update` never prompts for a password or restarts a router.

## Testing / updating

```sh
bash ~/dotfiles/setup.sh   # full, idempotent
dotfiles_update            # git pull + setup (warns before destroying local work)
source ~/.zshrc            # reload shell state only
```
