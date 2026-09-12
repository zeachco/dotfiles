-- NvChad's visual layer (base46 highlights, statusline, tabufline, nvdash, icons)
-- layered on top of LazyVim. The theme picker is intentionally left out -- see
-- lua/chadrc.lua: themes/current owns the theme so nvim follows the rest of the
-- dotfiles theme system instead of drifting from it.

-- base46 compiles highlights into a cache directory that records nothing about
-- which theme produced it, so after `theme-switch` writes a new base46-theme the
-- stale cache would keep being served. Track what the cache was built for.
local theme_marker = vim.fn.stdpath("data") .. "/base46-theme"

local function read_trimmed(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local contents = file:read("*all"):gsub("%s+", "")
  file:close()
  return contents ~= "" and contents or nil
end

local function ensure_base46_cache()
  local theme = require("nvconfig").base46.theme

  if vim.fn.isdirectory(vim.g.base46_cache) == 1 and read_trimmed(theme_marker) == theme then
    return
  end

  require("base46").load_all_highlights()

  local file = io.open(theme_marker, "w")
  if file then
    file:write(theme)
    file:close()
  end
end

-- base46 paints highlights directly with nvim_set_hl from the compiled cache; it
-- never goes through `:colorscheme`. Any `:colorscheme` call therefore wipes it,
-- and LazyVim issues one at startup (from themes/current/neovim.lua). Re-applying
-- on ColorScheme lets both coexist: LazyVim's colorscheme still fires the hook in
-- init.lua that syncs Herdr, and base46 wins the repaint.
local function apply_base46()
  local cache = vim.g.base46_cache
  if not cache or vim.fn.isdirectory(cache) == 0 then
    return
  end
  for _, name in ipairs(vim.fn.readdir(cache)) do
    pcall(dofile, cache .. name)
  end
end

return {
  {
    "nvchad/base46",
    lazy = true, -- loaded via require() below, only needs to be on the rtp
    dependencies = { "nvim-lua/plenary.nvim" },
    build = function()
      require("base46").load_all_highlights()
    end,
  },

  { "nvzone/volt", lazy = true },

  {
    "nvchad/ui",
    lazy = false,
    priority = 1000,
    -- base46 reads `require("nvconfig")`, which ships inside nvchad/ui, so both
    -- must be on the rtp before either is required.
    dependencies = { "nvchad/base46", "nvzone/volt" },
    config = function()
      ensure_base46_cache()
      apply_base46()

      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("base46_reapply", { clear = true }),
        callback = vim.schedule_wrap(apply_base46),
      })

      require("nvchad")
    end,
  },

  {
    "nvim-tree/nvim-web-devicons",
    opts = function()
      dofile(vim.g.base46_cache .. "devicons")
      return { override = require("nvchad.icons.devicons") }
    end,
  },

  -- LazyVim ships its own statusline, buffer line and dashboard; NvChad's
  -- replace them, so leaving both enabled would draw each twice.
  { "nvim-lualine/lualine.nvim", enabled = false },
  { "akinsho/bufferline.nvim", enabled = false },
  { "folke/snacks.nvim", opts = { dashboard = { enabled = false } } },
}
