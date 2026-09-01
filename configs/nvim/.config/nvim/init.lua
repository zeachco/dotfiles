-- On macOS the default stdpath("run") lives under $TMPDIR and, with a long
-- username, socket paths exceed the 104-byte unix socket limit, making
-- serverstart() fail with EINVAL (breaks fzf-lua). Use a short runtime dir.
if vim.fn.has("mac") == 1 and not vim.env.XDG_RUNTIME_DIR then
  local run_dir = vim.fn.expand("~/.cache/nvim/run")
  vim.fn.mkdir(run_dir, "p", tonumber("700", 8))
  vim.env.XDG_RUNTIME_DIR = run_dir
end

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

-- vim.cmd.colorscheme("retrobox")
-- vim.cmd.colorscheme("default")

-- Theme file override (populated by the `theme` command) only applies on macOS.
-- On other OSes (e.g. Omarchy) LazyVim's native light/dark detection is left alone.
local is_mac = vim.fn.has("mac") == 1

-- Function to get current system theme preference
local function get_system_theme()
  local handle = io.popen("defaults read -g AppleInterfaceStyle 2>/dev/null")
  if handle then
    local result = handle:read("*a")
    handle:close()
    return result:match("Dark") and "dark" or "light"
  end
  return "light" -- Fallback to light if command fails
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

-- Initial colorscheme setup (defer until plugins are loaded) -- macOS only
if is_mac then
  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    callback = update_colorscheme,
  })

  -- Create an autocommand to check periodically
  vim.api.nvim_create_autocmd("FocusGained", {
    pattern = "*",
    callback = update_colorscheme,
  })
end

-- Mapping from Neovim colorschemes to Herdr's built-in themes. Anything not
-- listed falls back to "terminal", which makes Herdr follow the terminal palette.
local nvim_to_herdr_theme_map = {
  ["kanagawa"] = "kanagawa",
  ["kanagawa-wave"] = "kanagawa",
  ["kanagawa-dragon"] = "kanagawa",
  ["kanagawa-lotus"] = "kanagawa-lotus",
  ["catppuccin"] = "catppuccin",
  ["catppuccin-mocha"] = "catppuccin",
  ["macchiato"] = "catppuccin",
  ["catppuccin-frappe"] = "catppuccin",
  ["catppuccin-latte"] = "catppuccin-latte",
  ["dracula"] = "dracula",
  ["gruvbox"] = "gruvbox",
  ["nord"] = "nord",
  ["tokyonight"] = "tokyo-night",
  ["tokyonight-night"] = "tokyo-night",
  ["tokyonight-storm"] = "tokyo-night",
  ["tokyonight-moon"] = "tokyo-night",
  ["tokyonight-day"] = "tokyo-night-day",
  ["rose-pine"] = "rose-pine",
  ["rose-pine-main"] = "rose-pine",
  ["rose-pine-moon"] = "rose-pine",
  ["rose-pine-dawn"] = "rose-pine-dawn",
  ["noctis-bordo"] = "vesper",
}

-- Apply transparency if enabled
vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "*",
  callback = function()
    -- Persist user's manual theme selection (only if not auto-switching)
    if is_mac and not vim.g._updating_colorscheme then
      local current_theme = vim.g.colors_name
      if current_theme then
        _G.update_current_theme_file(current_theme)
      end
    end

    -- Check if transparent_background is enabled
    local ok, plugin_config = pcall(require, "plugins.auto-theme-switcher")
    if ok and plugin_config.config and plugin_config.config.transparent_background then
      vim.api.nvim_set_hl(0, "Normal", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "NormalNC", { bg = "NONE" })
    end

    -- Sync Herdr's theme when running inside a Herdr session
    if os.getenv("HERDR_ENV") then
      local current_colorscheme = vim.g.colors_name
      local herdr_theme = nvim_to_herdr_theme_map[current_colorscheme] or "terminal"
      local herdr_config = vim.fn.expand("~/dotfiles/bin/herdr-config")

      if vim.fn.executable(herdr_config) == 1 then
        vim.fn.jobstart({ herdr_config, "set-theme", herdr_theme }, { detach = true })
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
