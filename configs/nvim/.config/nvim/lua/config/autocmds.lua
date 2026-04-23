-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

-- Monorepo workspace management
vim.api.nvim_create_autocmd("VimEnter", {
  pattern = "*",
  callback = function()
    local cwd = vim.fn.getcwd()

    -- Check if we're in the monoco monorepo root
    if cwd:match("/monoco$") then
      -- Auto-change to apps/scripts if that's your most common workspace
      local scripts_path = cwd .. "/apps/scripts"
      if vim.fn.isdirectory(scripts_path) == 1 then
        vim.cmd("cd " .. scripts_path)
        vim.notify("Changed to apps/scripts workspace", vim.log.levels.INFO)
      end
    end
  end,
})

-- User commands to switch between monorepo workspaces
vim.api.nvim_create_user_command("CdScripts", function()
  local monorepo_root = vim.fn.finddir(".git/..", vim.fn.getcwd() .. ";")
  if monorepo_root ~= "" then
    vim.cmd("cd " .. monorepo_root .. "/apps/scripts")
    vim.notify("Changed to apps/scripts", vim.log.levels.INFO)
  end
end, { desc = "Change to apps/scripts workspace" })

vim.api.nvim_create_user_command("CdRoot", function()
  local monorepo_root = vim.fn.finddir(".git/..", vim.fn.getcwd() .. ";")
  if monorepo_root ~= "" then
    vim.cmd("cd " .. monorepo_root)
    vim.notify("Changed to monorepo root", vim.log.levels.INFO)
  end
end, { desc = "Change to monorepo root" })

vim.api.nvim_create_user_command("CdApp", function(opts)
  local app_name = opts.args
  local monorepo_root = vim.fn.finddir(".git/..", vim.fn.getcwd() .. ";")
  if monorepo_root ~= "" then
    local app_path = monorepo_root .. "/apps/" .. app_name
    if vim.fn.isdirectory(app_path) == 1 then
      vim.cmd("cd " .. app_path)
      vim.notify("Changed to apps/" .. app_name, vim.log.levels.INFO)
    else
      vim.notify("Directory not found: " .. app_path, vim.log.levels.ERROR)
    end
  end
end, { nargs = 1, desc = "Change to apps/<name> workspace", complete = function()
  local monorepo_root = vim.fn.finddir(".git/..", vim.fn.getcwd() .. ";")
  if monorepo_root ~= "" then
    local apps_dir = monorepo_root .. "/apps"
    if vim.fn.isdirectory(apps_dir) == 1 then
      return vim.fn.readdir(apps_dir)
    end
  end
  return {}
end })
