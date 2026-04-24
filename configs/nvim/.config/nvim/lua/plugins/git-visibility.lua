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
        cwd = vim.fn.getcwd(), -- Use current working directory, not git root
      },
      pickers = {
        find_files = {
          hidden = true,
          -- Remove .git and .github from find_files ignore patterns
          find_command = { "rg", "--files", "--hidden", "--glob", "!**/.git/*", "--glob", "!**/.DS_Store" },
          cwd = vim.fn.getcwd(), -- Use current working directory
        },
        live_grep = {
          cwd = vim.fn.getcwd(), -- Use current working directory
        },
        grep_string = {
          cwd = vim.fn.getcwd(), -- Use current working directory
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