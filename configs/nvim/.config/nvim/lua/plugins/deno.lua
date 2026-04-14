-- Deno LSP configuration that auto-detects based on .vscode/settings.json
-- This configures denols to only activate in projects with deno.enable: true

-- Helper function to check if Deno is enabled in .vscode/settings.json
local function is_deno_enabled_in_vscode(root_dir)
  if not root_dir then
    return false
  end

  local vscode_settings = root_dir .. "/.vscode/settings.json"
  local file = io.open(vscode_settings, "r")

  if not file then
    return false
  end

  local content = file:read("*all")
  file:close()

  -- Simple JSON check for "deno.enable": true
  -- This handles various formatting: "deno.enable": true or "deno.enable":true
  return content:match('"deno%.enable"%s*:%s*true') ~= nil
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      -- Ensure servers table exists
      opts.servers = opts.servers or {}

      -- Configure denols
      opts.servers.denols = {
        -- Override root_dir to activate only where .vscode/settings.json has deno.enable: true
        root_dir = function(fname)
          local util = require("lspconfig.util")
          -- First, find a potential root with deno.json
          local root_dir = util.root_pattern("deno.json", "deno.jsonc")(fname)

          if not root_dir then
            return nil
          end

          -- Check if .vscode/settings.json enables Deno
          if is_deno_enabled_in_vscode(root_dir) then
            return root_dir
          end

          return nil
        end,
        settings = {
          deno = {
            enable = true,
            unstable = true,
            lint = true,
            suggest = {
              imports = {
                hosts = {
                  ["https://deno.land"] = true,
                  ["https://jsr.io"] = true,
                },
              },
            },
          },
        },
      }

      -- Override tsserver to disable where Deno is enabled
      opts.servers.tsserver = vim.tbl_deep_extend("force", opts.servers.tsserver or {}, {
        root_dir = function(fname)
          local util = require("lspconfig.util")
          -- Normal tsserver root detection
          local root_dir = util.root_pattern("package.json", "tsconfig.json", "jsconfig.json")(fname)

          if not root_dir then
            return nil
          end

          -- Don't activate if Deno is enabled in .vscode/settings.json
          if is_deno_enabled_in_vscode(root_dir) then
            return nil
          end

          return root_dir
        end,
      })

      return opts
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- Ensure TypeScript parser is installed for Deno
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "typescript", "tsx" })
      end
    end,
  },
}
