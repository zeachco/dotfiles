# Theme System

Cross-platform theme switching for terminal applications, based on [Omakub's theme mechanics](https://github.com/basecamp/omakub/tree/master/themes).

## Overview

This system provides a unified way to switch themes across multiple applications:
- **Neovim** - Text editor
- **Alacritty** - Terminal emulator
- **Herdr** - Terminal workspace manager
- **btop** - System monitor
- **Claude** - Light/dark appearance
- **Codex** - Matching Catppuccin light/dark syntax theme
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
    ├── neovim.lua         # Neovim/LazyVim theme plugin
    ├── alacritty.toml     # Alacritty terminal colors
    ├── herdr-theme        # Name of the matching Herdr built-in theme
    ├── btop.theme         # btop system monitor theme
    └── vscode.sh          # VS Code theme installer script
```

### File Descriptions

#### `neovim.lua`
LazyVim plugin configuration that installs and sets the colorscheme.

**Applied to:** `~/.config/nvim/lua/plugins/theme.lua`, with the selected
colorscheme persisted in `theme-light` and `theme-dark`.

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
```

#### `herdr-theme`
A single line naming the Herdr built-in theme that best matches this theme.

**Applied to:** the `theme.name` key of `~/.config/herdr/config.toml`, patched
in place by `bin/herdr-config`. On macOS that file is Stow-linked from
`configs/herdr`, so a theme switch leaves a one-line diff in the repo.

**Valid values:** `catppuccin`, `catppuccin-latte`, `terminal`, `tokyo-night`,
`tokyo-night-day`, `dracula`, `nord`, `gruvbox`, `gruvbox-light`, `one-dark`,
`one-light`, `solarized`, `solarized-light`, `kanagawa`, `kanagawa-lotus`,
`rose-pine`, `rose-pine-dawn`, `vesper`.

Use `terminal` when nothing matches: Herdr then adopts the host terminal's
palette, which `alacritty.toml` already themes. Verify a change with
`herdr config check`.

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
   - `neovim.lua`
   - `alacritty.toml`
   - `herdr-theme`
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

### Alacritty Integration

Make sure your `~/.config/alacritty/alacritty.toml` imports the theme:

```toml
import = ["~/dotfiles/themes/current/alacritty.toml"]
```

### Herdr Integration

Nothing to wire up: `bin/theme-switch` calls `bin/herdr-config sync-theme`,
which writes `theme.name` into `~/.config/herdr/config.toml` and asks the
running server to reload with `herdr server reload-config`.

### btop Integration

btop will automatically load themes from `~/.config/btop/themes/` when you switch.

### Claude and Codex Integration

When their config files exist, the switcher updates Claude to `light` or `dark`
and Codex to `catppuccin-latte` or `catppuccin-mocha`. Themes without explicit
appearance metadata are classified from their Alacritty background color.

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
- **Neovim**: Requires restart or `:Lazy reload`
- **Alacritty**: Reloads automatically
- **Herdr**: Reloads immediately in running sessions
- **btop**: Reloads automatically
- **VS Code**: Requires restart

## Credits

Inspired by [Omakub](https://github.com/basecamp/omakub) by Basecamp.
