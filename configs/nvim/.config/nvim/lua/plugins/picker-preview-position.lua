-- Open picker results where the preview was left, not where the file was last
-- seen.
--
-- fzf-lua jumps to the entry's own position (the grep match, the LSP
-- reference) and otherwise lets LazyVim's `last_loc` autocmd restore wherever
-- you left the file. Neither accounts for scrolling the preview: you can read
-- your way down to line 400 with <c-f>, hit <cr>, and land back on line 1.
--
-- The previewer records where scrolling left the cursor; the `enter` action
-- replays it once the real buffer is open.
return {
  "ibhagwan/fzf-lua",
  opts = function(_, opts)
    -- Guard against re-wrapping if the spec is evaluated more than once.
    if vim.g.dotfiles_fzf_preview_pos then
      return opts
    end
    vim.g.dotfiles_fzf_preview_pos = true

    local scrolled ---@type {entry: string?, path: string, lnum: number, col: number, topline: number}|nil

    local previewer = require("fzf-lua.previewer.builtin")

    -- Remember where the user scrolled to, per previewed entry.
    local scroll = previewer.base.scroll
    previewer.base.scroll = function(self, direction)
      scroll(self, direction)
      scrolled = nil
      local win = self.win and self.win.preview_winid
      local path = self.loaded_entry and self.loaded_entry.path
      if not path or direction == "reset" or not win or win < 0 or not vim.api.nvim_win_is_valid(win) then
        return
      end
      local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
      if ok then
        scrolled = {
          entry = self.last_entry,
          path = vim.fn.fnamemodify(path, ":p"),
          lnum = cursor[1],
          col = cursor[2],
          topline = vim.api.nvim_win_call(win, function()
            return vim.fn.line("w0")
          end),
        }
      end
    end

    -- Moving to another entry starts over.
    local display_entry = previewer.base.display_entry
    previewer.base.display_entry = function(self, entry_str)
      if scrolled and scrolled.entry ~= entry_str then
        scrolled = nil
      end
      return display_entry(self, entry_str)
    end

    local config = require("fzf-lua.config")
    local enter = config.defaults.actions.files["enter"]
    config.defaults.actions.files["enter"] = function(selected, o)
      local saved = scrolled
      scrolled = nil

      local ret = enter(selected, o)

      if saved and #selected == 1 then
        -- The action opens the file and places the cursor itself, so wait for
        -- it (and for LazyVim's `last_loc` autocmd) before overriding.
        vim.schedule(function()
          local buf = vim.api.nvim_get_current_buf()
          local name = vim.api.nvim_buf_get_name(buf)
          if name == "" or vim.fs.normalize(name) ~= vim.fs.normalize(saved.path) then
            return
          end
          local lnum = math.min(saved.lnum, vim.api.nvim_buf_line_count(buf))
          pcall(vim.api.nvim_win_set_cursor, 0, { lnum, saved.col })
          vim.fn.winrestview({ topline = saved.topline })
          vim.cmd("normal! zv")
        end)
      end

      return ret
    end

    return opts
  end,
}
