-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

-- vim.cmd.colorscheme("retrobox")
-- vim.cmd.colorscheme("default")

-- Function to get current system theme preference
local function get_system_theme()
  return "default"
  -- return vim.fn.system("defaults read -g AppleInterfaceStyle") == "Dark\n" and "dark" or "light"
end

-- Function to read theme from file
local function read_theme_file(theme_type)
  local filename = vim.fn.stdpath("config") .. "/theme-" .. theme_type
  local file = io.open(filename, "r")
  if file then
    local theme = file:read("*all"):gsub("%s+", "") -- Remove whitespace
    file:close()
    return theme
  end
  return nil
end

-- Function to write theme to file
local function write_theme_file(filename, theme_name)
  local file = io.open(filename, "w")
  if file then
    file:write(theme_name)
    file:close()
  end
end

-- Function to update colorscheme based on OS theme
local function update_colorscheme()
  vim.g._updating_colorscheme = true -- Flag to prevent persistence during automatic switching
  local system_theme = get_system_theme()
  local theme_name = read_theme_file(system_theme)

  if theme_name and theme_name ~= "" then
    -- Try to load the saved theme
    local success = pcall(vim.cmd.colorscheme, theme_name)
    if not success then
      -- Theme doesn't exist, fallback to default
      vim.notify("Theme '" .. theme_name .. "' not found, using default", vim.log.levels.WARN)
      local default_theme = system_theme == "dark" and "catppuccin-mocha" or "catppuccin-latte"
      pcall(vim.cmd.colorscheme, default_theme)
    end
  else
    -- Fallback to defaults if file doesn't exist or is empty
    local default_theme = system_theme == "dark" and "catppuccin-mocha" or "catppuccin-latte"
    pcall(vim.cmd.colorscheme, default_theme)
  end
  vim.g._updating_colorscheme = false
end

-- Function to update current theme file based on system theme
function _G.update_current_theme_file(theme_name)
  local system_theme = get_system_theme()
  local filename = vim.fn.stdpath("config") .. "/theme-" .. system_theme
  write_theme_file(filename, theme_name)
end

-- Theme persistence is now handled directly in the Snacks picker

-- Initial colorscheme setup (defer until plugins are loaded)
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  callback = update_colorscheme,
})

-- Create an autocommand to check periodically
vim.api.nvim_create_autocmd("FocusGained", {
  pattern = "*",
  callback = update_colorscheme,
})

-- Mapping from Neovim colorschemes to Zellij themes
local nvim_to_zellij_theme_map = {
  ["kanagawa"] = "kanagawa",
  ["kanagawa-wave"] = "kanagawa",
  ["kanagawa-dragon"] = "kanagawa",
  ["catppuccin"] = "catppuccin",
  ["catppuccin-mocha"] = "catppuccin",
  ["macchiato"] = "catppuccin",
  ["catppuccin-frappe"] = "catppuccin",
  ["catppuccin-latte"] = "catppuccin",
  ["dracula"] = "dracula",
  ["monokai"] = "monokai",
  ["gruvbox"] = "gruvbox",
  ["nord"] = "nord",
  ["tokyonight"] = "tokyo-night",
  ["tokyonight-night"] = "tokyo-night",
  ["tokyonight-storm"] = "tokyo-night",
  ["tokyonight-moon"] = "tokyo-night",
  ["rose-pine"] = "rose-pine",
  ["rose-pine-main"] = "rose-pine",
  ["rose-pine-moon"] = "rose-pine",
  ["rose-pine-dawn"] = "rose-pine",
  ["everforest"] = "everforest",
  ["noctis-bordo"] = "noctis-bordo",
}

-- Apply transparency if enabled
vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "*",
  callback = function()
    -- Check if transparent_background is enabled
    local ok, plugin_config = pcall(require, "plugins.auto-theme-switcher")
    if ok and plugin_config.config and plugin_config.config.transparent_background then
      vim.api.nvim_set_hl(0, "Normal", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "NormalNC", { bg = "NONE" })
    end

    -- Sync Zellij theme if running inside Zellij
    if os.getenv("ZELLIJ") then
      local current_colorscheme = vim.g.colors_name
      local zellij_theme = nvim_to_zellij_theme_map[current_colorscheme]

      if zellij_theme then
        -- Use zellij action to switch theme
        vim.fn.jobstart(
          string.format("zellij action switch-mode normal && zellij action switch-theme %s", zellij_theme),
          { detach = true }
        )
      end
    end
  end,
})

-- Disable conceal for markdown files
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.opt_local.conceallevel = 0
  end,
})
