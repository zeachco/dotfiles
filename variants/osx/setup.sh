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

if needs nvim; then
  brew tap homebrew/cask-fonts
  brew install --cask font-victor-mono-nerd-font
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

force_install aerospace Aerospace
force_install alacritty Alacritty
force_install chromium Chromium

# SketchyBar setup
if needs sketchybar; then
  brew trust --formula felixkratz/formulae/sketchybar
  brew tap FelixKratz/formulae
  brew install sketchybar
  # Install default Hack Nerd Font
  brew install --cask font-hack-nerd-font
  # Auto-start SketchyBar at login
  brew services start sketchybar 2>/dev/null || true
fi

stow_link sketchybar && brew services restart sketchybar
stow_link claude
stow_link zellij
stow_link aerospace
stow_link alacritty
stow_link alacritty-osx
stow_link nvim

# Generate alacritty os.toml with architecture-specific zellij path
# Alacritty uses execve(2) which doesn't search PATH, so we need absolute paths
# Intel Macs: /usr/local/bin/zellij
# Apple Silicon: /opt/homebrew/bin/zellij
ZELLIJ_PATH=$(which zellij 2>/dev/null || echo "${HOMEBREW_PREFIX:-/usr/local}/bin/zellij")

# Use bash wrapper to handle conditional session attach logic
rm -f ~/.config/alacritty/os.toml
cat >~/.config/alacritty/os.toml <<EOF
[terminal.shell]
program = "/bin/bash"
args = ["-c", "if $ZELLIJ_PATH list-sessions 2>/dev/null | grep -q '^1 '; then exec $ZELLIJ_PATH attach 1; else exec $ZELLIJ_PATH; fi"]
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
