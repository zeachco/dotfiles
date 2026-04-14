return {
  {
    "mg979/vim-visual-multi",
    lazy = false, -- Load immediately to ensure mappings work
    init = function()
      -- Configure vim-visual-multi to use Ctrl+D for word selection (like VSCode)
      vim.g.VM_maps = {
        ["Find Under"] = "<C-d>", -- Select word under cursor and add cursor to next occurrence
        ["Select All"] = "<C-l>", -- Select all occurrences of word in buffer (normal mode)
        ["Visual All"] = "<C-l>", -- Select all occurrences of visual selection (visual mode)
      }
    end,
  },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    config = function()
      require("catppuccin").setup({
        transparent_background = false,
      })
    end,
  },
  {
    "Mofiqul/dracula.nvim",
    name = "dracula",
    lazy = false,
    priority = 1000,
  },
  {
    "tanvirtin/monokai.nvim",
    name = "monokai",
    lazy = false,
    priority = 1000,
  },
  {
    "folke/snacks.nvim",
  },
  config = config, -- Export config for use elsewhere
}
