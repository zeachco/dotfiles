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

rm -f ~/.config/alacritty/os.toml
cat >~/.config/alacritty/os.toml <<EOF
[terminal.shell]
program = "$HERDR_PATH"
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
