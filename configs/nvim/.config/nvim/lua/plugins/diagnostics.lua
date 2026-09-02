-- Diagnostics display.
--
-- LazyVim applies its own `vim.diagnostic.config()` from the nvim-lspconfig
-- spec, which runs *after* lua/config/options.lua -- so anything set there is
-- silently overwritten and diagnostic settings have to live here instead.
--
-- Default: only ERRORs get inline virtual text. Warnings/hints/info stay quiet
-- (gutter sign only) until the cursor lands on the line, where `virtual_lines`
-- spells out the full message. `<leader>uw` toggles every severity back inline.

local virtual_text = {
  spacing = 4,
  source = "if_many",
  prefix = "●",
}

local errors_only = vim.tbl_extend("force", virtual_text, {
  severity = { min = vim.diagnostic.severity.ERROR },
})

vim.g.inline_warnings = false

local function apply()
  vim.diagnostic.config({ virtual_text = vim.g.inline_warnings and virtual_text or errors_only })
end

vim.keymap.set("n", "<leader>uw", function()
  vim.g.inline_warnings = not vim.g.inline_warnings
  apply()
  vim.notify((vim.g.inline_warnings and "Enabled" or "Disabled") .. " inline warnings")
end, { desc = "Toggle Inline Warnings" })

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        virtual_text = errors_only,
        -- Full message for whatever is under the cursor, any severity.
        virtual_lines = { current_line = true, wrap = true },
        underline = true,
        update_in_insert = false,
        severity_sort = true,
      },
    },
  },
}
