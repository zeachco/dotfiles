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
})

-- Preserve the legacy sliding workspace transition.
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "default", style = "slide" })
