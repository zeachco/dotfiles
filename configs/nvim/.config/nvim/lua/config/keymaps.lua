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

-- Every file this branch touches: committed since it forked from main, plus
-- staged, unstaged and untracked work. `<leader>gs` only shows the latter.
--
-- Built on `git_status` rather than `git_diff` so the entries carry the usual
-- status columns and untracked files preview as their full content. Lines are
-- emitted in porcelain v1 form ("XY path"): real `git status` output first,
-- then one "M  path"-style line per file changed on the branch, deduplicated
-- on the path so the working-tree state wins.
local function git_branch_files()
  local fzf = require("fzf-lua")
  local base
  for _, trunk in ipairs({ "main", "master" }) do
    local out = vim.fn.systemlist({ "git", "merge-base", trunk, "HEAD" })
    if vim.v.shell_error == 0 and out[1] and out[1] ~= "" then
      base = out[1]
      break
    end
  end
  if not base then
    vim.notify("No main/master branch to compare against", vim.log.levels.WARN)
    return
  end
  local defaults = fzf.config.globals.previewers.git_diff
  fzf.git_status({
    cmd = table.concat({
      "{ git -c color.status=false --no-optional-locks status --porcelain=v1 -u;",
      "git --no-pager diff --name-status " .. base .. " --",
      [[| awk -F'\t' '{ printf "%s  %s\n", substr($1, 1, 1), $NF }'; }]],
      [[| awk '{ p = substr($0, 4); if (!seen[p]++) print }']],
    }, " "),
    previewer = {
      _ctor = defaults._ctor,
      _fn_git_icons = defaults._fn_git_icons,
      pager = defaults.pager,
      cmd_modified = "git diff --color " .. base,
      cmd_deleted = "git diff --color " .. base .. " --",
      cmd_untracked = defaults.cmd_untracked,
    },
    prompt = "BranchFiles> ",
    header = false,
    -- Own memory slot so the remembered filter is not shared with <leader>gs.
    __resume_key = "git.status_branch",
  })
end

vim.keymap.set({ "n", "i", "x", "s" }, "<C-g>", git_branch_files, { desc = "Git Status (branch + working tree files)" })
-- LazyVim's plain `git_diff` picker is superseded by the one above.
pcall(vim.keymap.del, "n", "<leader>gd")
