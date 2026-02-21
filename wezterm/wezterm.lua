local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Theme
config.color_scheme = "tokyonight_night"
-- Custom overrides
config.colors = {
	background = "#000000", -- Deep black (darker than default #1a1b26)
}
config.window_background_opacity = 0.80
config.text_background_opacity = 1.0
config.macos_window_background_blur = 20

-- Font
config.font = wezterm.font("JetBrainsMono Nerd Font", { weight = "DemiBold" })
config.font_size = 12.0
config.line_height = 1.2

-- Window
config.window_decorations = "RESIZE" -- No title bar, just resizable window
config.window_padding = {
	left = 12,
	right = 0,
	top = 12,
	bottom = 0,
}

-- Tab bar
config.hide_tab_bar_if_only_one_tab = true

-- Cursor
config.default_cursor_style = "BlinkingBar"

-- Performance
config.max_fps = 120

-- Keybindings
config.keys = {
	{
		key = "k",
		mods = "CMD",
		action = wezterm.action_callback(function(window, pane)
			local proc = pane:get_foreground_process_name() or ""
			if proc:find("tmux") then
				-- Clear only the current tmux pane: Ctrl+U clears any partial input,
				-- then clear the viewport and wipe tmux pane scrollback
				pane:send_text("\x15clear; tmux clear-history\n")
			else
				window:perform_action(wezterm.action.ClearScrollback("ScrollbackAndViewport"), pane)
			end
		end),
	},
	{
		key = "a",
		mods = "CMD",
		action = wezterm.action_callback(function(window, pane)
			local dims = pane:get_dimensions()
			local txt = pane:get_text_from_region(0, dims.scrollback_top, 0, dims.scrollback_top + dims.scrollback_rows)
			window:copy_to_clipboard(txt:match("^%s*(.-)%s*$")) -- trim leading and trailing whitespace
		end),
	},
	-- Option + Arrow keys for word navigation
	{ key = "LeftArrow", mods = "OPT", action = wezterm.action.SendString("\x1bb") },
	{ key = "RightArrow", mods = "OPT", action = wezterm.action.SendString("\x1bf") },
}

return config
