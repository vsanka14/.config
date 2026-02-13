local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Tokyo Night 'night' color scheme (from tokyonight.nvim extras)
config.color_scheme_dirs = { os.getenv("HOME") .. "/.local/share/nvim/lazy/tokyonight.nvim/extras/wezterm" }
config.color_scheme = "tokyonight_night"

-- Custom overrides
config.colors = {
	background = "#000000", -- Deep black (darker than default #1a1b26)
}
config.window_background_opacity = 0.75
config.text_background_opacity = 1.0
config.macos_window_background_blur = 20

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
