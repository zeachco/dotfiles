-- NodeJS / TypeScript debugging.
--
-- The `dap.core` and `lang.typescript` extras already provide the pwa-node
-- adapter (backed by mason's js-debug-adapter), a "Launch file" config and an
-- "Attach" config that prompts for a process. This adds the missing piece:
-- attaching to an already running `node --inspect` process on its debug port.
--
-- Note: js-debug only binds breakpoints in code parsed *after* the attach
-- completes. Prefer `node --inspect-brk` when you need breakpoints in code that
-- runs at startup; plain `--inspect` on an already-running process leaves those
-- breakpoints provisional (unverified).
return {
  {
    "mfussenegger/nvim-dap",
    optional = true,
    opts = function()
      local dap = require("dap")

      for _, language in ipairs({ "typescript", "javascript", "typescriptreact", "javascriptreact" }) do
        dap.configurations[language] = dap.configurations[language] or {}
        table.insert(dap.configurations[language], {
          type = "pwa-node",
          request = "attach",
          name = "Attach to Node app (port 9229)",
          address = "localhost",
          port = 9229,
          cwd = "${workspaceFolder}",
          restart = true,
          sourceMaps = true,
          skipFiles = {
            "<node_internals>/**",
            "node_modules/**",
          },
          resolveSourceMapLocations = {
            "${workspaceFolder}/**",
            "!**/node_modules/**",
          },
        })
      end
    end,
  },
}
