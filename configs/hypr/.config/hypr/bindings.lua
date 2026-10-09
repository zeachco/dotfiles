-- Keep personal keybinding overrides here. Omarchy defaults remain active.
-- See current bindings with: omarchy menu keybindings --print

-- Open tmux on demand in Foot at the current terminal-aware directory.
-- SUPER + SHIFT + RETURN is Omarchy's default Browser shortcut.
hl.unbind("SUPER + SHIFT + RETURN")
o.bind(
  "SUPER + SHIFT + RETURN",
  "Tmux",
  'uwsm-app -- foot --working-directory="$(omarchy-cmd-terminal-cwd)" tmux new-session -A -s main'
)

-- Keep the Tmux terminal shortcut even though preinstalled app bindings are disabled.
o.bind("SUPER + ALT + RETURN", "Tmux", { omarchy = "terminal-tmux" })

-- Preserve the legacy numpad workspace mechanics.
local numpad_workspace_keys = {
  "KP_End",
  "KP_Down",
  "KP_Next",
  "KP_Left",
  "KP_Begin",
  "KP_Right",
  "KP_Home",
  "KP_Up",
  "KP_Prior",
  "KP_Insert",
}

for workspace, key in ipairs(numpad_workspace_keys) do
  o.bind(
    "SUPER + " .. key,
    "Switch to workspace " .. workspace,
    hl.dsp.focus({ workspace = tostring(workspace) })
  )
  o.bind(
    "SUPER + SHIFT + " .. key,
    "Move window to workspace " .. workspace,
    hl.dsp.window.move({ workspace = tostring(workspace) })
  )
end

-- SUPER + MINUS / EQUAL resize the focused window's width. Omarchy binds them
-- to `resizeactive`, which the scrolling layout clamps to the space left on
-- screen, so a column can never grow past the viewport edge. On scrolling
-- workspaces use `colresize` instead: it sets the column width directly (up to
-- a full screen) and re-fits the column into view. Dwindle keeps `resizeactive`.
local function resize_width(px, fraction)
  return function()
    local workspace = hl.get_active_workspace()
    if workspace and workspace.tiled_layout == "scrolling" then
      hl.dispatch(hl.dsp.layout("colresize " .. fraction))
    else
      hl.dispatch(hl.dsp.window.resize({ x = px, y = 0, relative = true }))
    end
  end
end

hl.unbind("SUPER + code:20")
hl.unbind("SUPER + code:21")
o.bind("SUPER + code:20", "Shrink window width (column on scrolling)", resize_width(-100, "-0.05"))
o.bind("SUPER + code:21", "Expand window width (column on scrolling)", resize_width(100, "+0.05"))
