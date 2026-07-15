-- `themes/current` is machine-local and initialized before this config is stowed.
local theme_file = vim.fn.expand("~/dotfiles/themes/current/neovim.lua")
local ok, theme = pcall(dofile, theme_file)

if ok and type(theme) == "table" then
  return theme
end

vim.schedule(function()
  vim.notify("Unable to load current theme: " .. theme_file, vim.log.levels.WARN)
end)

return {}
