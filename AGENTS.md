# AI Agent Guide: Dotfiles Architecture

Cross-platform dotfiles using two-tier profiles (shared base + OS-specific overrides) and GNU Stow for config symlinks.

## Flow: setup.sh → OS detection → install_profile("shared") → install_profile(OS_variant)

**Core files**: `setup.sh` (orchestrator), `utils.sh` (install/stow_link/install_profile), `variants/*/setup.sh` (packages), `variants/*/profile.sh` (shell config)

## OS Detection (setup.sh:17-36)
Linux → /etc/arch-release or pacman → archlinux | else → debian  
Overrides: $TERMUX_VERSION → termux | lsb_release=Ubuntu → ubuntu  
Darwin → osx

## Variants (variants/*)
**Inheritance**: shared sourced FIRST → OS-specific (allows function shadowing)

| Variant | PM | Stow Configs | Notes |
|---------|----|--------------| ------|
| shared | agnostic | alacritty | Base: git, rg, fd, gh, fzf, zellij |
| debian | apt | claude, alacritty-debian, nvim | Core tools, ollama |
| ubuntu | apt | Same as debian | + devbox, shortcuts.sh (GNOME keys) |
| osx | brew | 7 pkgs (aerospace, sketchybar, etc) | Generates zellij os.toml |
| archlinux | pacman+yay | waybar, wireplumber | AUR helper, 20+ pac*/yay* functions |
| termux | pkg | None | Android-specific, redefined killport/network |
| omarchy | pacman | hypr, zellij-omarchy | Setup-only, modifies Hypr bindings |

## Stow System (configs/ → ~/)
16 packages mirror home structure: `configs/nvim/.config/nvim/`, `configs/alacritty/.config/alacritty/`  
**stow_link()** (utils.sh:124-148): auto-removes conflicts, uses --restow fallback  
**Override pattern**: base (alacritty, zellij) + OS variants (alacritty-osx, zellij-omarchy)

## install_profile() (utils.sh:29-44)
1. Run variants/$variant/setup.sh  
2. Copy profile.sh → ~/.dotfiles_$variant  
3. Source in shell: `[[ -f ~/.dotfiles_$variant ]] && source ~/.dotfiles_$variant # zeachco-dotfiles`

**clean_imports()**: strips old `# zeachco-dotfiles` lines before reinstall

## Key Functions (variants/shared/profile.sh)
**clone [repo]**: GitHub shorthand | **killport [port]**: kill process | **check_for_devbox()**: auto-enters devbox shell  
**Git**: gco, gs, gd, gci, gp (via `_set` - prints before exec) | **_worktrees.sh**: jira_claude, zellij integration  
**OS-specific**: archlinux (pacup, yayin), osx (docker wrapper, dark mode), termux (battery, notify)

## Testing
`bash ~/dotfiles/setup.sh` (full) | `dotfiles_update` (remote pull) | `source ~/.zshrc` (reload)

---

## Neovim/LazyVim: Make .git and .github Directories Visible

**Problem:** In LazyVim, `.git` and `.github` directories are hidden from both the file tree (Neo-tree) and fuzzy finder (Telescope).

**Solution:** Create `/lua/plugins/git-visibility.lua` with the following configuration:

```lua
return {
  -- Configure Telescope to show .git and .github directories
  {
    "nvim-telescope/telescope.nvim",
    opts = {
      defaults = {
        file_ignore_patterns = {
          "node_modules/",
          ".devbox/nix/",
          ".venv/",
          -- Removed .git and .github from ignore patterns
        },
        hidden = true, -- Show hidden files
      },
      pickers = {
        find_files = {
          hidden = true,
          -- Remove .git and .github from find_files ignore patterns
          find_command = { "rg", "--files", "--hidden", "--glob", "!**/.git/*", "--glob", "!**/.DS_Store" },
        },
      },
    },
  },

  -- Configure Neo-tree to show .git and .github directories
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      filesystem = {
        filtered_items = {
          visible = true, -- Show filtered items
          hide_dotfiles = false,
          hide_gitignored = false,
          hide_by_name = {
            -- Remove .git and .github from hidden items
            ".DS_Store",
            "thumbs.db",
          },
          hide_by_pattern = {
            -- You can add patterns here if needed
          },
          always_show = {
            ".git",
            ".github",
            ".gitignore",
            ".gitattributes",
          },
          never_show = {
            ".DS_Store",
            "thumbs.db",
          },
        },
        follow_current_file = {
          enabled = true,
        },
      },
    },
  },
}
```

**What this fixes:**
- Makes `.git` and `.github` directories visible in Neo-tree file explorer
- Makes `.git` and `.github` directories searchable with Telescope fuzzy finder
- Shows hidden files while still excluding unnecessary files like `.DS_Store`
- Allows browsing git-related files and GitHub workflows/actions

**Usage:** Place this file in your Neovim config at `~/.config/nvim/lua/plugins/git-visibility.lua` and restart Neovim.