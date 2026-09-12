-- NvChad's config file (must match the structure of nvchad/ui's lua/nvconfig.lua).
-- NvChad's own theme picker is deliberately NOT installed: `themes/current` owns
-- the theme so Neovim stays in sync with alacritty, btop, herdr and the rest.
-- `bin/theme-switch` copies the selected theme's `base46-theme` into
-- themes/current, and this file reads it at startup.

---@type ChadrcConfig
local M = {}

local function current_base46_theme()
  local file = io.open(vim.fn.expand("~/dotfiles/themes/current/base46-theme"), "r")
  if not file then
    return nil
  end
  local name = file:read("*all"):gsub("%s+", "")
  file:close()
  return name ~= "" and name or nil
end

M.base46 = {
  -- onedark is base46's own default; only used when themes/current has no mapping.
  theme = current_base46_theme() or "onedark",
}

M.ui = {
  statusline = { theme = "default", separator_style = "round" },
  -- lazyload=false so the tab bar is there from the first buffer, not the second.
  tabufline = { enabled = true, lazyload = false },
}

M.nvdash = { load_on_startup = true }

return M
