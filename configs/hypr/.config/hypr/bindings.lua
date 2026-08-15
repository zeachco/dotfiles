-- Keep personal keybinding overrides here. Omarchy defaults remain active.
-- See current bindings with: omarchy menu keybindings --print

-- Open Zellij on demand in Foot at the current terminal-aware directory.
-- SUPER + SHIFT + RETURN is Omarchy's default Browser shortcut.
hl.unbind("SUPER + SHIFT + RETURN")
o.bind(
  "SUPER + SHIFT + RETURN",
  "Zellij",
  'uwsm-app -- foot --working-directory="$(omarchy-cmd-terminal-cwd)" zellij'
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
