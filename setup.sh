#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ "$(uname -s)" = Darwin ] && ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are required to compile dotfiles." >&2
  echo "Run 'xcode-select --install', finish the installation, then rerun setup.sh." >&2
  exit 1
fi

if [ -x "$HOME/.cargo/bin/cargo" ]; then
  . "$HOME/.cargo/env"
fi

install_curl() {
  if command -v curl >/dev/null 2>&1; then return; fi
  if command -v pkg >/dev/null 2>&1; then pkg install -y curl
  elif command -v apt-get >/dev/null 2>&1; then sudo apt-get install -y curl
  elif command -v pacman >/dev/null 2>&1; then sudo pacman -S --needed --noconfirm curl
  else
    echo "curl is required to bootstrap Rust" >&2
    exit 1
  fi
}

if ! command -v cargo >/dev/null 2>&1; then
  if [ -n "${TERMUX_VERSION:-}" ] || printf '%s' "${PREFIX:-}" | grep -q com.termux; then
    pkg install -y rust
  else
    install_curl
    curl --proto '=https' --tlsv1.2 -fsS https://sh.rustup.rs | sh -s -- -y --profile minimal
    # rustup writes this environment file for POSIX shells regardless of the
    # user's interactive login shell.
    . "$HOME/.cargo/env"
  fi
fi

cd "$ROOT"
cargo build --release --locked

mkdir -p "$HOME/.local/bin"
cp target/release/dotfiles "$HOME/.local/bin/dotfiles.new"
chmod 755 "$HOME/.local/bin/dotfiles.new"
mv "$HOME/.local/bin/dotfiles.new" "$HOME/.local/bin/dotfiles"

DOTFILES_ROOT="$ROOT" exec "$HOME/.local/bin/dotfiles" apply "$@"
