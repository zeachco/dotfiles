-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Keep Omarchy's window-manager bindings without its app launchers.
omarchy_preinstalled_bindings = false

-- Omarchy's default/hypr/apps/1password.lua tags 1Password "+floating-window",
-- which system.lua turns into float + center + 875x600. A later `tile = true`
-- rule does not out-rank it, so stop the file loading at all: require() honours
-- a pre-seeded package.loaded entry. Re-add its no_screen_share rule below.
-- If an Omarchy update renames that file, this stub silently stops working and
-- 1Password floats again.
package.loaded["default.hypr.apps.1password"] = true

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Load dotfiles-owned overrides after Omarchy's defaults.
require("hypr.monitors")
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

-- Kept from the stubbed-out Omarchy 1Password defaults: stay out of screen shares.
o.window("^(1[p|P]assword)$", { no_screen_share = true })
