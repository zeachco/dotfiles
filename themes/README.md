# Theme System

Cross-platform theme switching for terminal applications, based on [Omakub's theme mechanics](https://github.com/basecamp/omakub/tree/master/themes).

## Overview

This system provides a unified way to switch themes across multiple applications:
- **tmux** - Terminal multiplexer
- **Neovim** - Text editor
- **Alacritty** - Terminal emulator
- **Zellij** - Terminal multiplexer (alternative to tmux)
- **btop** - System monitor
- **VS Code** - Code editor

## Usage

Run the theme switcher:

```bash
./bin/theme-switch
```

Or add `bin/` to your PATH:

```bash
export PATH="$HOME/dotfiles/bin:$PATH"
theme-switch
```

### Interactive Selection

If you have [gum](https://github.com/charmbracelet/gum) installed, you'll get an interactive menu. Otherwise, a traditional numbered selection will be used.

Install gum:
```bash
# macOS
brew install gum

# Linux
# See: https://github.com/charmbracelet/gum#installation
```

## Theme Structure

Each theme is a directory under `themes/` containing application-specific theme files:

```
themes/
└── tokyo-night/
    ├── tmux.conf          # tmux theme
    ├── neovim.lua         # Neovim/LazyVim theme plugin
    ├── alacritty.toml     # Alacritty terminal colors
    ├── zellij.kdl         # Zellij theme
    ├── btop.theme         # btop system monitor theme
    └── vscode.sh          # VS Code theme installer script
```

### File Descriptions

#### `tmux.conf`
tmux theme configuration with status bar colors, pane borders, and window status styling.

**Applied to:** `~/.config/tmux/theme.conf`

#### `neovim.lua`
LazyVim plugin configuration that installs and sets the colorscheme.

**Applied to:** `~/.config/nvim/lua/plugins/theme.lua`

**Format:**
```lua
return {
  {
    "author/theme-plugin",  -- Theme plugin (if needed)
    lazy = false,
    priority = 1000,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "theme-name",
    },
  },
}
```

#### `alacritty.toml`
Alacritty color scheme in TOML format.

**Applied to:** `~/.config/alacritty/theme.toml`

**Format:**
```toml
[colors.primary]
background = "#1a1b26"
foreground = "#a9b1d6"

[colors.normal]
black = "#32344a"
# ... more colors
```

#### `zellij.kdl`
Zellij theme in KDL format.

**Applied to:** `~/.config/zellij/themes/<theme-name>.kdl`

**Format:**
```kdl
themes {
  theme-name {
    bg "#1a1b26"
    fg "#a9b1d6"
    # ... more colors
  }
}
```

#### `btop.theme`
btop system monitor theme with color definitions for CPU, memory, network graphs.

**Applied to:** `~/.config/btop/themes/<theme-name>.theme`

**Format:**
```
theme[main_bg]="#1a1b26"
theme[main_fg]="#a9b1d6"
# ... more theme settings
```

#### `vscode.sh`
Bash script that installs VS Code extension and updates settings.

**Format:**
```bash
#!/bin/bash
VSC_THEME="Tokyo Night"
VSC_EXTENSION="enkia.tokyo-night"

if command -v code &>/dev/null; then
  code --install-extension "$VSC_EXTENSION" >/dev/null 2>&1
  sed -i.bak "s/\"workbench.colorTheme\": \".*\"/\"workbench.colorTheme\": \"$VSC_THEME\"/g" \
    "$HOME/.config/Code/User/settings.json"
fi
```

## Adding a New Theme

1. **Create theme directory:**
   ```bash
   mkdir themes/my-theme
   ```

2. **Add theme files** (at minimum, create files for the applications you use):
   - `tmux.conf`
   - `neovim.lua`
   - `alacritty.toml`
   - `zellij.kdl` (optional)
   - `btop.theme` (optional)
   - `vscode.sh` (optional)

3. **Update the theme list** in `bin/theme-switch`:
   ```bash
   THEME_NAMES=("Tokyo Night" "Catppuccin" "Gruvbox" "Nord" "My Theme")
   ```

4. **Test the theme:**
   ```bash
   ./bin/theme-switch
   ```

## Architecture

The theme switcher follows these principles:

1. **Separation of Concerns** - Each application has its own theme file
2. **Graceful Degradation** - Only applies themes for installed applications
3. **Declarative Configuration** - Theme files contain only colors/styling, no logic
4. **Centralized Switching** - Single script orchestrates all changes
5. **Naming Convention** - Human-readable names ("Tokyo Night") converted to file paths ("tokyo-night")

## Integration with Your Dotfiles

### tmux Integration

Make sure your `~/.config/tmux/tmux.conf` sources the theme file:

```tmux
# Load theme
source-file ~/.config/tmux/theme.conf
```

### Alacritty Integration

Make sure your `~/.config/alacritty/alacritty.toml` imports the theme:

```toml
import = ["~/.config/alacritty/theme.toml"]
```

### Zellij Integration

Make sure your `~/.config/zellij/config.kdl` references the theme:

```kdl
theme "tokyo-night"
```

### btop Integration

btop will automatically load themes from `~/.config/btop/themes/` when you switch.

## Available Themes

- **Tokyo Night** - Dark theme with vibrant colors (currently implemented)
- **Catppuccin** - Placeholder (to be implemented)
- **Gruvbox** - Placeholder (to be implemented)
- **Nord** - Placeholder (to be implemented)

## Cross-Platform Compatibility

This system works on:
- ✅ macOS
- ✅ Linux
- ✅ WSL (Windows Subsystem for Linux)

Note: GNOME desktop themes and desktop backgrounds are intentionally excluded for cross-platform compatibility.

## Automatic Reloading

The theme switcher automatically reloads configurations where possible:
- **tmux**: Reloaded automatically if running in tmux
- **Neovim**: Requires restart or `:Lazy reload`
- **Alacritty**: Reloads automatically
- **Zellij**: May require restart
- **btop**: Reloads automatically
- **VS Code**: Requires restart

## Credits

Inspired by [Omakub](https://github.com/basecamp/omakub) by Basecamp.
