-- Keep animations enabled and constrain overly wide single-window layouts.
hl.config({
	general = {
		gaps_in = 2,
		gaps_out = 2,
		-- layout = "scrolling",
	},
	animations = {
		enabled = true,
	},
	layout = {
		single_window_aspect_ratio = { 9, 6 },
	},
	scrolling = {
		-- Hyprland only scrolls a hover-focused column into view when at least
		-- this fraction of it is already on screen (default 0.4). With 0, hovering
		-- the sliver of a half-hidden column also brings it fully into view.
		follow_min_visible = 0,
	},
})

-- Preserve the legacy sliding workspace transition.
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "default", style = "slide" })

-- Every window: fully opaque when focused, 0.8 when inactive. Loaded after
-- Omarchy's defaults so it out-ranks the per-app transparent_window rules.
o.window({ class = ".*" }, { opacity = "1.0 0.8" })
