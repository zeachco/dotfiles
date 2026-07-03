-- Deno LSP configuration that auto-detects based on deno.json/deno.jsonc presence
-- This configures denols to activate only in projects with a deno.json(c) file,
-- and disables tsserver in that same root so they don't fight over the same files.

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      -- Ensure servers table exists
      opts.servers = opts.servers or {}

      -- Configure denols
      opts.servers.denols = {
        -- root_dir must call on_dir(root) — Nvim 0.11+'s native LSP API invokes
        -- this as root_dir(bufnr, on_dir), not the old lspconfig root_pattern(fname) style.
        root_dir = function(bufnr, on_dir)
          on_dir(vim.fs.root(bufnr, { "deno.json", "deno.jsonc" }))
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

      -- Override tsserver to disable where a deno.json(c) root is found
      opts.servers.tsserver = vim.tbl_deep_extend("force", opts.servers.tsserver or {}, {
        root_dir = function(bufnr, on_dir)
          local root_dir = vim.fs.root(bufnr, { "package.json", "tsconfig.json", "jsconfig.json" })

          -- Don't activate if this root also has a deno.json(c)
          if root_dir and vim.fs.root(bufnr, { "deno.json", "deno.jsonc" }) then
            root_dir = nil
          end

          on_dir(root_dir)
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
