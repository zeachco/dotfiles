return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- nvim-lspconfig only starts denols when deno.json, deno.jsonc, or
        -- deno.lock identifies the current project.
        denols = {},
      },
    },
  },
}
