# AI Agent Guide: Rust Dotfiles Architecture

Cross-platform dotfiles with a POSIX bootstrap, a dependency-free Rust CLI,
declarative TOML profiles, generated shell adapters, and GNU Stow.

## Flow

`setup.sh → bootstrap Rust → cargo build --locked → dotfiles apply`

The Rust CLI detects the platform and account login shell, composes the shared
and platform profiles, displays a plan, applies confirmed actions, and saves the
selection to `~/.config/dotfiles/state.toml`.

## Source of truth

- `src/`: detection, parser/model, apply engine, shell rendering, CLI helpers
- `manifests/profiles/`: shared policy plus OS/environment overlays
- `manifests/shell.toml`: portable aliases, exports, and PATH entries
- `manifests/shell/`: platform-specific alias overlays
- `configs/`: Stow packages mirroring the home directory

Profiles inherit as `shared → family → overlay`: Ubuntu inherits Debian;
Omarchy inherits Arch; WSL is detected as an environment on its Linux distro.

The manifest parser intentionally accepts a small TOML subset: quoted strings,
quoted-string arrays, and named sections. Keep arrays on one line and package
entries in `command|apt|pacman|brew|pkg` form.

## Invariants

- Never run package-manager full upgrades during setup.
- Never reset or discard a dirty dotfiles checkout.
- Validate every referenced Stow package before applying any changes.
- Back up conflicting Stow targets rather than deleting them.
- Keep `~/.config` physical and use Stow's `--no-folding`; generated state and
  shell files must never be written through a folded package directory.
- Configure only the account's default Bash, Zsh, or Fish shell.
- Preserve public shortcut names through native aliases or Rust subcommands.
- Do not hand-edit generated files under `~/.config/dotfiles/generated/`.
- Keep the Rust CLI dependency-free unless a dependency is strongly justified
  across macOS, glibc Linux, WSL, and native Termux.

## Verification

```sh
cargo test --locked
cargo build --release --locked
sh -n setup.sh
for p in debian ubuntu archlinux osx termux omarchy; do
  DOTFILES_PLATFORM=$p DOTFILES_SHELL=fish target/release/dotfiles plan
done
target/release/dotfiles shell render bash | bash -n
target/release/dotfiles shell render zsh | zsh -n
target/release/dotfiles shell render fish | fish -n
git diff --check
```

Tests and planning may use `DOTFILES_PLATFORM` and `DOTFILES_SHELL`; normal
installation must use real platform and account-shell detection.
