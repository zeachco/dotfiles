-- Rust / native debugging via CodeLLDB.
--
-- VS Code's CodeLLDB extension registers itself under the type id `lldb`, so any
-- .vscode/launch.json written for it (e.g. dev/r3000) asks nvim-dap for an
-- adapter by that name. The `dap.core` extra auto-loads those launch.json files
-- but registers no such adapter, which fails with:
--   Config references missing adapter `lldb`.
-- mason-nvim-dap registers codelldb under its own package name, not `lldb`, so
-- the alias below is what actually resolves those configs.

local function codelldb_path()
  local mason = vim.fn.stdpath("data") .. "/mason/bin/codelldb"
  if vim.fn.executable(mason) == 1 then
    return mason
  end
  return vim.fn.exepath("codelldb")
end

-- CodeLLDB accepts a `cargo` key and resolves the built binary itself. nvim-dap
-- has no such support, so without this those configs launch with no `program`.
-- Build with --message-format=json and pick the artifact matching cargo.filter.
local function cargo_executable(cargo, cwd)
  local args = { "cargo" }
  vim.list_extend(args, cargo.args or {})
  table.insert(args, "--message-format=json")

  local result = vim.system(args, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    error("cargo build failed:\n" .. (result.stderr or ""))
  end

  local filter = cargo.filter or {}
  local matches = {}

  for line in (result.stdout or ""):gmatch("[^\n]+") do
    local ok, msg = pcall(vim.json.decode, line)
    if ok and type(msg) == "table" and msg.reason == "compiler-artifact" and msg.executable then
      local target = msg.target or {}
      local name_ok = not filter.name or target.name == filter.name
      local kind_ok = not filter.kind or vim.tbl_contains(target.kind or {}, filter.kind)
      if name_ok and kind_ok then
        table.insert(matches, msg.executable)
      end
    end
  end

  if #matches == 0 then
    error("no cargo artifact matched filter: " .. vim.inspect(filter))
  end

  return matches[#matches]
end

return {
  {
    "jay-babu/mason-nvim-dap.nvim",
    optional = true,
    opts = { ensure_installed = { "codelldb" } },
  },

  {
    "mfussenegger/nvim-dap",
    optional = true,
    opts = function()
      local dap = require("dap")

      dap.adapters.lldb = {
        type = "server",
        port = "${port}",
        executable = {
          command = codelldb_path(),
          args = { "--port", "${port}" },
        },
        -- Runs after nvim-dap has expanded ${workspaceFolder} and friends.
        enrich_config = function(config, on_config)
          local final = vim.deepcopy(config)

          if final.cargo then
            -- cwd can still be unexpanded or absent depending on the config.
            local cwd = final.cwd
            if not cwd or cwd:find("${", 1, true) or vim.fn.isdirectory(cwd) == 0 then
              cwd = vim.fn.getcwd()
            end

            final.program = cargo_executable(final.cargo, cwd)
            final.cargo = nil
          end

          on_config(final)
        end,
      }
    end,
  },
}
