-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
-- require("telescope").setup({
--   defaults = {
--     file_ignore_patterns = {
--       "node_modules",
--       ".devbox/nix",
--       ".git",
--       ".venv",
--     },
--   },
-- })

-- Disable relative line numbers
-- vim.opt.relativenumber = false

-- Auto-save on focus loss
vim.api.nvim_create_autocmd({ "FocusLost", "BufLeave" }, {
  pattern = "*",
  callback = function()
    -- Avoid saving when entering fzf-lua or other special buffers
    if vim.bo.filetype == "fzf" or vim.bo.buftype ~= "" then
      return
    end
    if vim.bo.modified and not vim.bo.readonly and vim.fn.expand("%") ~= "" then
      vim.cmd("silent! write")
    end
  end,
})
