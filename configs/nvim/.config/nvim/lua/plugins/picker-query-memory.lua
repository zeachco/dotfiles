-- Two pickers reopen with the filter you last typed in them: the LSP reference
-- list (`gr`) and the branch files picker (`<C-g>`, see config/keymaps.lua).
-- A `!test` filter stays on across openings even though the results are
-- recomputed. Every other picker (file search, grep, buffers, ...) always
-- opens with an empty prompt.
--
-- fzf-lua already collects what we need: it runs fzf with `--print-query` and
-- after *every* exit -- accept, `<esc>`, `<c-c>` -- stores the typed prompt per
-- provider via `config.resume_set` (see `core.fzf`). What it never does is feed
-- that memory back into the next plain invocation; only `:FzfLua resume` reuses
-- it, and that also replays the stale result list and window options.
--
-- So we hook `config.normalize_opts`, the one choke point every provider runs
-- through, and copy the remembered query into the freshly normalized options
-- for the two allowed pickers. The window is then built by fzf-lua exactly as
-- if the query had been passed by the caller (`--query=<q>`).
--
-- `<c-c>` forgets the query (fzf-lua already routes that key through an action,
-- we just swap the no-op handler for one that clears the memory); `<esc>` keeps
-- it, and so does opening a result.
--
-- Only the typed text is remembered; toggles such as `<a-i>`/`<a-h>` reset on
-- every open. fzf-lua keys every LSP location picker as "lsp", so `gr`, `gd`
-- and `gi` would share a slot; we key them by picker name instead, which is
-- also what lets the allowlist single out `gr`.
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

    -- Memory keys, as fzf-lua derives them for `:FzfLua resume`.
    local remembered_keys = { ["lsp.lsp_references"] = true, ["git.status_branch"] = true }

    local function memory_key(o)
      local key = o.__resume_key
      if key == nil then
        return nil
      end
      return (tostring(key):match("[^%s]+$"))
    end

    -- The stored entry is fzf-lua's saved `__call_opts` table, with the query
    -- written into it afterwards. Read through `resume_get`: keys such as
    -- `git.status_branch` are dotted paths in `__resume_map`, not flat keys.
    local function remembered(o)
      local data = config.resume_get(nil, o)
      return type(data) == "table" and data or nil
    end

    local function forget(o)
      config.resume_set("query", nil, { __resume_key = o.__resume_key })
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

    local normalize = config.normalize_opts

    config.normalize_opts = function(o, globals, resume_key)
      -- Providers re-enter through `fzf_exec`; only the first pass decides.
      if type(o) == "table" and o._normalized then
        return normalize(o, globals, resume_key)
      end

      -- Key LSP location pickers by their public name (`lsp_references`, ...),
      -- which the API wrapper records before calling the provider.
      if globals == "lsp" and resume_key == nil and (type(o) ~= "table" or o.__resume_key == nil) then
        local info = fzf.get_info()
        if info and info.cmd then
          resume_key = "lsp." .. info.cmd
        end
      end

      local ret = normalize(o, globals, resume_key)
      if type(ret) ~= "table" or not remembered_keys[memory_key(ret)] then
        return ret
      end

      -- `resume=true` replays fzf-lua's own snapshot, and a caller-provided
      -- query wins over the memory.
      local data = remembered(ret)
      if data and not ret.resume and ret.query == nil and data.query and data.query ~= "" then
        ret.query = data.query
      end
      clear_on_ctrl_c(ret)

      return ret
    end

    return opts
  end,
}
