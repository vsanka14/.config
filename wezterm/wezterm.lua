local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Tokyo Night 'night' color scheme
config.colors = {
	-- Foreground and background
	foreground = "#c0caf5", -- Tokyo Night foreground
	background = "#000000", -- Deep black (darker than Tokyo Night default)

	-- Cursor
	cursor_bg = "#c0caf5", -- Tokyo Night foreground
	cursor_fg = "#1a1b26", -- Tokyo Night background
	cursor_border = "#c0caf5",

	-- Selection
	selection_bg = "#283457", -- Tokyo Night selection
	selection_fg = "#c0caf5", -- Tokyo Night foreground

	-- ANSI colors (normal) - Tokyo Night palette
	ansi = {
		"#15161e", -- black
		"#f7768e", -- red
		"#9ece6a", -- green
		"#e0af68", -- yellow
		"#7aa2f7", -- blue
		"#bb9af7", -- magenta
		"#7dcfff", -- cyan
		"#a9b1d6", -- white
	},

	-- ANSI colors (bright) - Tokyo Night palette
	brights = {
		"#414868", -- bright black
		"#f7768e", -- bright red
		"#9ece6a", -- bright green
		"#e0af68", -- bright yellow
		"#7aa2f7", -- bright blue
		"#bb9af7", -- bright magenta
		"#7dcfff", -- bright cyan
		"#c0caf5", -- bright white
	},
}

config.window_background_opacity = 0.75 -- More opaque for darker background
config.text_background_opacity = 1.0 -- Ensure text background is opaque
config.macos_window_background_blur = 20 -- Blur effect for frosted glass look

-- Font
config.font = wezterm.font("JetBrainsMono Nerd Font", { weight = "Bold" })
config.font_size = 12.0

-- Window
config.window_decorations = "RESIZE" -- No title bar, just resizable window
config.window_padding = {
	left = 0,
	right = 0,
	top = 0,
	bottom = 0,
}

-- Tab bar
config.hide_tab_bar_if_only_one_tab = true

-- Launch into tmux session switcher on startup
config.default_prog = {
	"/bin/zsh",
	"-l",
	"-c",
	"~/.config/scripts/tmux-session-switcher.sh || exec tmux new-session -As main",
}

-- Cursor
config.default_cursor_style = "BlinkingBar"

-- Performance
config.max_fps = 120

-- Keybindings
config.keys = {
	{ key = "k", mods = "CMD", action = wezterm.action.SendKey({ key = "l", mods = "CTRL" }) },
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
