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

# llama.cpp, used in router mode by the com.zeachco.llama-router launchd agent below.
# The brew formula depends on `ggml`, which on Apple Silicon is built with
# GGML_METAL=ON (only Intel macOS gets METAL=OFF) and GGML_BACKEND_DL=ON, with the
# backends dlopen'd from $(brew --prefix)/opt/ggml/libexec -- so this is a
# Metal-accelerated build with no source compile needed.
#
# Checked with `brew list` rather than `needs llama-server`: v0.3.0 ships both a
# multi-tool `llama` and per-subcommand `llama-*` binaries, so a binary-name probe is
# fragile across upgrades. Same idiom as the font-jetbrains-mono-nerd-font check above.
if ! brew list llama.cpp >/dev/null 2>&1; then
  echo -e "${WARN}installing ${NORM}llama.cpp..."
  brew install llama.cpp
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

# Install the llama.cpp router as a launchd user agent. Must come after the
# `brew install llama.cpp` above: the installer bakes an absolute binary path into the
# plist and skips itself entirely when that binary is missing.
#
# Invoked with a literal `bash`, NOT "$SHELL": utils.sh runs this file as
# `$SHELL <script>` and $SHELL is /bin/zsh here, so the shebang is ignored. install.sh
# uses `set -euo pipefail` plus ${BASH_SOURCE[0]}, and under zsh that resolves to the
# CALLER's cwd without aborting -- a silently wrong path, not an error.
#
# `|| echo` so a router failure does not abort the rest of the macOS setup.
bash "$DOT_DIR/variants/osx/llama-router/install.sh" ||
  echo -e "${FAIL}llama router install failed${NORM}"

# The model set (~29 GB) is NOT fetched here by default. install_profile runs this
# file on every `dotfiles_update`, there is no consent step anywhere in the setup
# flow, and the router does not need models to start -- verifying it boots and answers
# /health with an empty ~/models is a better first milestone than a 29 GB download.
if [[ "${LOS_FETCH_MODELS:-}" == "1" ]]; then
  bash "$DOT_DIR/configs/llama/fetch-models-osx.sh" ||
    echo -e "${FAIL}llama model fetch failed${NORM}"
fi
