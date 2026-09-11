#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

if [ -d "$HOME/.oh-my-zsh" ]; then
  echo "ohmyzsh is already installed"
else
  echo "installing ohmyzsh..."
  yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  source ~/.zshrc
fi

if needs brew; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install tiles
[[ -d /Applications/Tiles.app ]] || brew install tiles

if needs devbox; then
  curl -fsSL https://get.jetify.com/devbox | bash
  # brew trust --formula pilat/devbox/devbox
  # brew tap pilat/devbox
  # brew install devbox
fi

# JetBrains Mono Nerd Font (alacritty terminal font)
if ! brew list --cask font-jetbrains-mono-nerd-font &>/dev/null; then
  echo -e "${WARN}installing ${NORM}font-jetbrains-mono-nerd-font..."
  brew install --cask font-jetbrains-mono-nerd-font
fi

if needs nvim; then
  brew install --HEAD neovim
fi

if needs colima; then
  brew install colima
fi

# arg 1 is the brew namespace, arg 2 is the Application namespace
function force_install {
  if needs "$1"; then
    install "$1"
  fi
  # Always unquarantine (macOS updates can re-quarantine apps)
  xattr -d com.apple.quarantine /Applications/$2.app 2>/dev/null || echo "$2 already authorized"
}

force_install alacritty Alacritty
force_install chromium Chromium

# SketchyBar setup
if needs sketchybar; then
  brew trust --formula felixkratz/formulae/sketchybar
  brew tap FelixKratz/formulae
  brew install sketchybar
  # Install default Hack Nerd Font
  brew install --cask font-hack-nerd-font
fi

# Install blueutil for bluetooth control in sketchybar
needs blueutil && install blueutil

stow_link sketchybar
stow_link aerospace
stow_link alacritty
stow_link alacritty-osx
stow_link herdr
stow_link nvim

# The shared profile already ran herdr-config, but that was before the Stow
# link existed; re-apply so the keymap and theme land in the linked file.
if command -v herdr &>/dev/null; then
  "$DOT_DIR/bin/herdr-config" ensure-keys
  "$DOT_DIR/bin/herdr-config" sync-theme
fi

# Generate alacritty os.toml with the absolute herdr path
# Alacritty uses execve(2) which doesn't search PATH, so we need absolute paths
# herdr with no args launches or attaches to the persistent session
HERDR_PATH=$(which herdr 2>/dev/null || echo "$HOME/.local/bin/herdr")

# Launch through an interactive login shell so the herdr *server* inherits a
# real PATH. Alacritty starts from launchd with PATH=/usr/bin:/bin:/usr/sbin:
# /sbin, the client spawns the server as a child, and the server hands its own
# environment to every plugin command and [[keys.command]] entry. Without this,
# anything outside those four directories fails to spawn with "No such file or
# directory (os error 2)" (visible in `herdr plugin log`).
#
# Both flags are load-bearing, and -i is the subtle one: zsh sources ~/.zshrc
# only for *interactive* shells, and ~/.zshrc is where every PATH export lives
# (bun, ~/.local/bin, lmstudio, gcloud) because ~/.zshenv is empty and there is
# no ~/.zprofile. A plain `-l -c` therefore gets only path_helper's PATH, which
# does carry /opt/homebrew/bin -- so `gh` and the brew binaries resolve and the
# server looks fixed, while `bun` alone still fails and takes every PR Tracker
# hook and action with it. Verify a change here from a clean environment, not
# from an inherited one:
#   env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
#     "$SHELL" -l -i -c 'command -v bun'
#
# Pane shells were never affected: terminal.shell_mode = "auto" already makes
# them interactive login shells on macOS, which is why $PATH looks fine inside
# a pane. A PATH change reaches the server only when Alacritty is relaunched --
# restarting the server alone respawns it from the client's stale environment.
LOGIN_SHELL="${SHELL:-/bin/zsh}"

rm -f ~/.config/alacritty/os.toml
cat >~/.config/alacritty/os.toml <<EOF
[terminal.shell]
program = "$LOGIN_SHELL"
args = ["-l", "-i", "-c", "exec '$HERDR_PATH'"]
EOF

# call `defaults delete <property>` to reset to default
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
defaults write -g QLPanelAnimationDuration -float 0
defaults write com.apple.dock launchanim -bool false
defaults write com.apple.finder DisableAllAnimations -bool true
defaults write com.apple.dock springboard-show-duration -float .1
defaults write com.apple.dock springboard-hide-duration -float .1
defaults write com.apple.dock expose-animation-duration -float 0.1
# Allows grab windows with Ctrl+CMD
defaults write -g NSWindowShouldDragOnGesture -bool true

# All llama.cpp setup (brew install, router install, optional model fetch via
# LOS_FETCH_MODELS=1) lives in llamacpp/.
bash "$DOT_DIR/llamacpp/osx/setup.sh"

# Must stay last: the Stow relinks above leave a running Alacritty reloaded
# against a half-written config, which drops the Nerd Font. See
# nudge_alacritty_reload in utils.sh.
nudge_alacritty_reload
