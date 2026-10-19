-- Reopening a picker resumes the query you last typed in it.
--
-- Type `const data =` in the file search, pick a file, hit `<leader>/` again and
-- the prompt comes back with `const data =` already in it. Same for the LSP
-- reference list (`gr`): a `!test` filter stays on across openings, even though
-- the results themselves are recomputed for the new symbol.
--
-- fzf-lua already collects what we need: it runs fzf with `--print-query` and
-- after *every* exit -- accept, `<esc>`, `<c-c>` -- stores the typed prompt per
-- provider via `config.resume_set` (see `core.fzf`). What it never does is feed
-- that memory back into the next plain invocation; only `:FzfLua resume` reuses
-- it, and that also replays the stale result list and window options.
--
-- So we hook `config.normalize_opts`, the one choke point every provider runs
-- through, and copy the remembered query into the freshly normalized options.
-- The window is then built by fzf-lua exactly as if the query had been passed
-- by the caller (`--query=<q>`, or for grep-like pickers `opts.search`).
--
-- `<c-c>` forgets the query (fzf-lua already routes that key through an action,
-- we just swap the no-op handler for one that clears the memory); `<esc>` keeps
-- it, and so does opening a result.
--
-- Three flavours of query, restored the same way they were stored:
--   * grep / live_grep pass the prompt to ripgrep as `search` (a regex, never
--     fzf-escaped), so it is restored as `search` + `no_esc`.
--   * live_workspace_symbols sends the prompt to the server as `lsp_query`.
--   * everything else filters client-side with fzf's extended query syntax
--     (`!test`, `'exact`, `^prefix`), stored and restored as `query`.
--
-- Known limits, on purpose:
--   * Only the typed text is remembered. Toggles such as `<a-i>`/`<a-h>`
--     reset on every open. A glob typed after ` -- ` in live_grep is part of
--     `search`, so it does come back.
--   * grep and live_grep share one memory (fzf-lua keys both as "grep"), which
--     is what lets `<c-g>` round-trip between them. If you left in fuzzy mode
--     (`<c-g>`, then an extra filter such as `!test`), `<leader>/` reopens in
--     fuzzy mode with both the regex and the filter in place.
--   * fzf-lua keys every LSP location picker as "lsp", so `gr`, `gd` and `gi`
--     would share a filter; we key them by picker name instead.
--   * `vim.ui.select` and code actions never get a remembered query -- a stale
--     filter there would hide the options you came for.
--
-- The highlighted row comes back too. fzf's `focus` event reports the row
-- index (`{n}`), which we store next to the query; on reopen a one-shot `load`
-- bind replays it with `pos(N)`. fzf clamps `pos` to the list, so a shorter
-- list just lands on its last row.
return {
  "ibhagwan/fzf-lua",
  opts = function(_, opts)
    -- Guard against wrapping twice if the spec is evaluated more than once.
    if vim.g.dotfiles_picker_query_memory then
      return opts
    end
    vim.g.dotfiles_picker_query_memory = true

    local fzf = require("fzf-lua")
    local config = fzf.config
    local actions = fzf.actions
    local shell = require("fzf-lua.shell")
    local utils = require("fzf-lua.utils")

    -- fzf-lua keys its resume memory the same way; reuse its key derivation so
    -- we read exactly the entry that `:FzfLua resume` would have used.
    local function memory_key(o)
      local key = o.__resume_key
      if key == nil then
        return nil
      end
      return (tostring(key):match("[^%s]+$"))
    end

    -- The stored entry is fzf-lua's saved `__call_opts` table, with the query
    -- written into it afterwards, so it holds `search` (grep) or `query`
    -- (client-side filter) depending on the provider.
    -- Read through `resume_get`: keys such as `git.diff` are dotted paths in
    -- `__resume_map` (`__resume_map.git.diff`), not flat string keys.
    local function remembered(o)
      if memory_key(o) == nil then
        return nil
      end
      local data = config.resume_get(nil, o)
      return type(data) == "table" and data or nil
    end

    local function restore(o, data)
      if data.search and data.search ~= "" then
        o.search, o.no_esc = data.search, true
      elseif data.query and data.query ~= "" then
        o.query = data.query
      elseif data.lsp_query and data.lsp_query ~= "" then
        o.lsp_query = data.lsp_query
      end
    end

    -- `{n}` and `pos()` need real fzf (not skim) with event binds.
    local function cursor_supported(o)
      return utils.has(o, "fzf", { 0, 45 })
    end

    -- Every cursor move reports its row through fzf-lua's RPC bridge, the same
    -- channel the builtin previewer already uses on each focus.
    local function remember_cursor(o)
      if not cursor_supported(o) or o.keymap.fzf["focus"] ~= nil then
        return
      end
      local key = o.__resume_key
      o.keymap.fzf["focus"] = "execute-silent:"
        .. shell.stringify_data(function(selection)
          local n = tonumber(selection and selection[1])
          if n then
            config.resume_set("cursor", n + 1, { __resume_key = key })
          end
        end, o, "{n}")
    end

    -- Replay the row once the first result set has loaded. Only once: live
    -- pickers fire `load` after every keystroke and must keep their cursor.
    local function restore_cursor(o, pos)
      if not cursor_supported(o) or o.keymap.fzf["load"] ~= nil or not pos or pos < 1 then
        return
      end
      local done = false
      o.keymap.fzf["load"] = "transform:"
        .. shell.stringify_data(function()
          if done then
            return ""
          end
          done = true
          return string.format("pos(%d)", pos)
        end, o, "")
    end

    local function forget(o)
      for _, what in ipairs({ "query", "search", "lsp_query", "cursor" }) do
        config.resume_set(what, nil, { __resume_key = o.__resume_key })
      end
    end

    -- `<c-c>` clearing: fzf-lua binds it to `actions.dummy_abort` (a no-op) so
    -- the query can still be saved, which makes it the perfect hook -- leave
    -- any other binding alone.
    local function clear_on_ctrl_c(o)
      o.actions = o.actions or {}
      o.keymap = o.keymap or {}
      o.keymap.fzf = o.keymap.fzf or {}
      local bound = o.keymap.fzf["ctrl-c"]
      local action = o.actions["ctrl-c"]
      if (bound == nil or bound == "abort") and (action == nil or action == actions.dummy_abort) then
        o.actions["ctrl-c"] = function(_, oo)
          forget(oo)
        end
      end
    end

    -- A caller that already knows the query (`grep_cword`, `grep_visual`, the
    -- ctrl-g switch between grep and live_grep) wins over the memory.
    local function caller_has_query(o)
      return o.query ~= nil or o.search ~= nil or o.lsp_query ~= nil or o.regex ~= nil
    end

    -- Pickers whose prompt is a menu, not a search: never pre-fill them.
    local skip_globals = { ui_select = true, ["lsp.code_actions"] = true }

    local normalize = config.normalize_opts

    config.normalize_opts = function(o, globals, resume_key)
      -- Providers re-enter through `fzf_exec`; only the first pass decides.
      if type(o) == "table" and o._normalized then
        return normalize(o, globals, resume_key)
      end

      -- Every LSP location picker normalizes with the shared "lsp" globals, so
      -- without this `gr` and `gd` would read the same memory slot. Key them
      -- by the public picker name (`lsp_references`, `lsp_definitions`, ...),
      -- which the API wrapper records before calling the provider.
      if globals == "lsp" and resume_key == nil and (type(o) ~= "table" or o.__resume_key == nil) then
        local info = fzf.get_info()
        if info and info.cmd then
          resume_key = "lsp." .. info.cmd
        end
      end

      local ret = normalize(o, globals, resume_key)
      if type(ret) ~= "table" then
        return ret
      end

      -- `complete` drives LSP completion, `no_resume` is the builtin picker;
      -- a stale filter there is noise.
      if ret.complete or ret.no_resume or skip_globals[globals] then
        return ret
      end

      -- `resume=true` replays fzf-lua's own snapshot (the ctrl-g switch), so
      -- only the text restore steps aside; `<c-c>` and the cursor still apply.
      local data = remembered(ret)
      if data and not ret.resume and not caller_has_query(ret) then
        restore(ret, data)
      end
      clear_on_ctrl_c(ret)
      ret.keymap.fzf = ret.keymap.fzf or {}
      remember_cursor(ret)
      if data then
        restore_cursor(ret, tonumber(data.cursor))
      end

      return ret
    end

    -- grep and live_grep share the "grep" memory. Leaving from fuzzy mode
    -- (after ctrl-g) stores the extra filter as `query`; leaving from live mode
    -- stores the regex as `search`. A `query` left over from an earlier fuzzy
    -- session would wrongly flag fuzzy mode, so a live-mode exit drops it.
    local resume_set = config.resume_set
    config.resume_set = function(what, val, o)
      resume_set(what, val, o)
      if what == "search" and o and memory_key(o) == "grep" then
        resume_set("query", nil, o)
      end
    end

    -- Reopening live_grep after a fuzzy-mode exit comes back in fuzzy mode:
    -- rg runs the remembered regex and fzf gets the remembered filter, exactly
    -- the picker you closed. ctrl-g still flips back to live mode.
    local live_grep = fzf.live_grep
    fzf.live_grep = function(o)
      o = o or {}
      local data = config.__resume_map and config.__resume_map.grep
      if
        type(o) == "table"
        and not o.resume
        and not caller_has_query(o)
        and type(data) == "table"
        and data.search
        and data.search ~= ""
        and data.query
        and data.query ~= ""
      then
        return fzf.grep(vim.tbl_extend("force", o, { search = data.search, no_esc = true, query = data.query }))
      end
      return live_grep(o)
    end

    return opts
  end,
}
