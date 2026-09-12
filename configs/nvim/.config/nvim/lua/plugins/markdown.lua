-- Markdown rendering tweaks on top of LazyVim's `lang.markdown` extra.
--
-- The extra deliberately strips render-markdown back to a plain look
-- (`heading.icons = {}`, `checkbox.enabled = false`). This restores the parts
-- that carry information, and drops the two markdownlint rules that fire on
-- every long line of a spec document.
--
-- Note: wide tables only render correctly with `wrap` off -- render-markdown
-- draws borders as virtual text on a single screen line, so a wrapped row
-- shreds them. That side lives in lua/config/autocmds.lua.

return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      heading = {
        -- Back to the numbered glyphs; LazyVim blanks these out, which leaves
        -- the raw '##' markers visible.
        icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
      },
      checkbox = {
        enabled = true,
      },
      pipe_table = {
        preset = "round",
      },
    },
  },

  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      -- MD013 (line-length) and MD060 (table-column-style) are pure style
      -- rules. On a spec doc they account for essentially every gutter marker
      -- while catching nothing real, so filter them out and keep the rest.
      local ignored = { MD013 = true, MD060 = true }
      local linter = require("lint").linters["markdownlint-cli2"]
      local parse = linter.parser
      linter.parser = function(output, bufnr, linter_cwd)
        return vim.tbl_filter(function(d)
          -- Messages look like: `error MD060/table-column-style Table column ...`
          local code = d.message:match("(MD%d+)/")
          return not (code and ignored[code])
        end, parse(output, bufnr, linter_cwd))
      end
      return opts
    end,
  },
}
