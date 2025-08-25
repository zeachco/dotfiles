# AI Agent Configurations

This document contains configurations and fixes that AI agents (like Claude) can apply to improve development environments.

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