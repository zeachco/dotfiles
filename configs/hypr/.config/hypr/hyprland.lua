-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Keep Omarchy's window-manager bindings without its app launchers.
omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Load dotfiles-owned overrides after Omarchy's defaults.
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Prevent terminal activation requests, including Codex prompt completion,
-- from stealing focus.
o.window("Alacritty", { focus_on_activate = false })

-- Omarchy floats Steam and its presentation terminals by default. Keep Steam,
-- Updates, and Install terminals tiled instead.
o.window("steam", { tile = true })
o.window("org\\.omarchy\\.terminal", { tile = true })
