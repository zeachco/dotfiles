-- Keymaps are automatically loaded on the VeryLazy event.

-- Override the default colorscheme picker to add persistence.
vim.keymap.set("n", "<leader>uC", function()
  require("snacks").picker.colorschemes({
    confirm = function(picker, item)
      picker:close()
      if item then
        picker.preview.state.colorscheme = nil
        vim.schedule(function()
          vim.cmd("colorscheme " .. item.text)
          _G.update_current_theme_file(item.text)

          local cmd = string.format("$HOME/dotfiles/bin/theme-switch '%s'", item.text)
          vim.fn.jobstart(cmd, { detach = true })
          vim.notify("Executed: " .. cmd, vim.log.levels.INFO)
        end)
      end
    end,
  })
end, { desc = "Colorscheme with Preview (persisted)" })

local function current_root()
  if LazyVim and LazyVim.root then
    local ok, root = pcall(LazyVim.root)
    if ok and root and root ~= "" then
      return root
    end
  end

  return vim.fn.getcwd()
end

local function write_buffer()
  if vim.api.nvim_buf_get_name(0) ~= "" then
    vim.cmd.write()
    return
  end

  local root = current_root()
  vim.ui.input({ prompt = "Save relative to " .. root .. ": " }, function(path)
    if not path or path == "" then
      return
    end

    local target = vim.fs.normalize(vim.fs.joinpath(root, path))
    local ok, err = pcall(vim.cmd.write, vim.fn.fnameescape(target))
    if not ok then
      vim.notify(err, vim.log.levels.ERROR)
    end
  end)
end

vim.keymap.set({ "n", "i", "x", "s" }, "<C-n>", "<Cmd>enew<CR>", { desc = "New buffer" })
vim.keymap.set({ "n", "i", "x", "s" }, "<C-s>", write_buffer, { desc = "Save buffer" })
vim.keymap.set({ "n", "i", "x", "s" }, "<C-S-s>", "<Cmd>wall<CR>", { desc = "Save all buffers" })

function _G.dotfiles_write_abbreviation()
  if vim.fn.getcmdtype() == ":" and vim.fn.getcmdline() == "w" then
    return "lua dotfiles_write_buffer()"
  end
  return "w"
end

_G.dotfiles_write_buffer = write_buffer
vim.cmd([[cnoreabbrev <expr> w v:lua.dotfiles_write_abbreviation()]])
