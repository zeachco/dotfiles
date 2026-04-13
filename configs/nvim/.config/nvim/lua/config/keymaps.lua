-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Override the default colorscheme picker to add persistence
vim.keymap.set("n", "<leader>uC", function()
  require("snacks").picker.colorschemes({
    confirm = function(picker, item)
      picker:close()
      if item then
        picker.preview.state.colorscheme = nil
        vim.schedule(function()
          vim.cmd("colorscheme " .. item.text)
          -- Persist the theme selection
          _G.update_current_theme_file(item.text)
          -- Execute shell command with selected theme
          local cmd = string.format("$HOME/dotfiles/bin/theme-switch '%s'", item.text)
          vim.fn.jobstart(cmd, { detach = true })
          vim.notify("Executed: " .. cmd, vim.log.levels.INFO)
        end)
      end
    end,
  })
end, { desc = "Colorscheme with Preview (persisted)" })
