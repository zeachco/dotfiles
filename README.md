# Cross-platform dotfiles

Shell-neutral machine setup for Arch Linux, Debian, Ubuntu, WSL, macOS,
Omarchy, and Termux. Installation policy lives in TOML manifests and is applied
by a dependency-free Rust CLI. Bash, Zsh, and Fish receive small generated
adapters; none of them is used as the configuration runtime.

## Install

Clone the repository and run the POSIX bootstrap from any shell:

```sh
git clone git@github.com:zeachco/dotfiles.git ~/dotfiles
~/dotfiles/setup.sh
```

The bootstrap installs a pinned Rust toolchain with rustup on macOS/Linux/WSL,
or Termux's patched Rust package on Android. It compiles `dotfiles`, installs it
under `~/.local/bin`, detects the account's default shell, displays a plan, and
asks before changing the machine. For unattended setup:

```sh
~/dotfiles/setup.sh --yes
```

Setup never performs a full operating-system upgrade.

## CLI

```text
dotfiles plan [--features F]  Preview changes
dotfiles apply [--yes] [--features core,dev]
                              Reconcile packages, configs, and shell adapter
dotfiles features             Show selected feature groups
dotfiles features core dev    Save a different feature selection
dotfiles doctor               Diagnose an installation
dotfiles update [--yes]       Fast-forward, rebuild, and reapply safely
dotfiles shell render fish    Print a generated adapter
```

The first run preselects the complete historical platform profile. Feature
groups (`core`, `dev`, `editor`, `desktop`, `ai`, `fonts`, `containers`,
`hardware`, and `system-tweaks`) can be deselected at the prompt and are saved
in `~/.config/dotfiles/state.toml`.

`dotfiles update` refuses to run in a dirty checkout and uses
`git pull --ff-only`; it never resets local work. The existing
`dotfiles_update` and `update_dotfiles` shell commands call this safe workflow.

## Architecture

- `setup.sh` is a minimal POSIX bootstrap. It does not contain machine policy.
- `src/` contains platform detection, manifest validation, planning/apply,
  Stow conflict backups, shell generation, updates, and portable helpers.
- `manifests/profiles/` composes `shared` with platform overlays.
- `manifests/shell.toml` and `manifests/shell/` define portable and
  platform-specific aliases and environment values.
- `configs/` remains a GNU Stow tree targeting the user's home directory.

Before Stow reconciles a conflicting target, the CLI moves it into a timestamped
directory under `~/.local/state/dotfiles/backups/`.

## Shell integration

Only the configured login shell is changed:

- Bash: managed source blocks in `~/.bashrc` and `~/.bash_profile`
- Zsh: a managed source block in `~/.zshrc`
- Fish: `~/.config/fish/conf.d/zeachco-dotfiles.fish`

Generated files live in `~/.config/dotfiles/generated/`. Change the TOML
manifests instead of editing generated files. Unsupported login shells fail
before any shell configuration is written.

## Development

```sh
cargo test --locked
cargo build --release --locked
DOTFILES_PLATFORM=ubuntu DOTFILES_SHELL=fish cargo run -- plan
cargo run -- shell render fish | fish -n
```

`DOTFILES_PLATFORM` and `DOTFILES_SHELL` are deterministic test overrides. They
are not needed during normal installation.
