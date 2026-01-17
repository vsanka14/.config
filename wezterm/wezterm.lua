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

-- Custom tab title formatting for clear borders (Tokyo Night colors)
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local background = "#1a1b26" -- Tokyo Night background
	local foreground = "#c0caf5" -- Tokyo Night foreground
	local edge_foreground = "#414868" -- Tokyo Night bright black

	if tab.is_active then
		background = "#7dcfff" -- Tokyo Night cyan
		foreground = "#1a1b26" -- Tokyo Night background
	elseif hover then
		background = "#24283b" -- Tokyo Night terminal black
		foreground = "#c0caf5" -- Tokyo Night foreground
	end

	local title = tab.active_pane.title
	-- Truncate title if it's too long
	local max = 20
	if #title > max then
		title = title:sub(1, max - 3) .. "..."
	end

	title = " " .. tab.tab_index + 1 .. ": " .. title .. " "

	return {
		{ Background = { Color = background } },
		{ Foreground = { Color = foreground } },
		{ Text = title },
		{ Foreground = { Color = edge_foreground } },
		{ Text = "|" },
	}
end)

config.window_background_opacity = 0.80 -- More opaque for darker background
config.text_background_opacity = 1.0 -- Ensure text background is opaque
config.macos_window_background_blur = 20 -- Blur effect for frosted glass look

-- Font
config.font = wezterm.font("JetBrainsMono Nerd Font", { weight = "Bold" })
config.font_size = 13.0

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
config.tab_bar_at_bottom = false
config.tab_max_width = 32
config.use_fancy_tab_bar = false -- Retro tab bar renders inside terminal grid, avoiding pixel misalignment

-- Cursor
config.default_cursor_style = "BlinkingBar"

-- Keybindings
config.keys = {
	{ key = "LeftArrow", mods = "CMD|SHIFT", action = wezterm.action.MoveTabRelative(-1) },
	{ key = "RightArrow", mods = "CMD|SHIFT", action = wezterm.action.MoveTabRelative(1) },
	{ key = "k", mods = "CMD", action = wezterm.action.SendKey({ key = "l", mods = "CTRL" }) },
	{ key = "j", mods = "CMD", action = wezterm.action.SendKey({ key = "j", mods = "CTRL" }) }, -- newline (ctrl+j intercepted by AeroSpace)
	{ key = "w", mods = "CMD", action = wezterm.action.CloseCurrentTab({ confirm = true }) },
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

	-- Split panes
	{
		key = "|",
		mods = "CMD|SHIFT",
		action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }),
	},
	{ key = "_", mods = "CMD|SHIFT", action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }) },

	-- Navigate panes
	{ key = "h", mods = "CMD|OPT", action = wezterm.action.ActivatePaneDirection("Left") },
	{ key = "l", mods = "CMD|OPT", action = wezterm.action.ActivatePaneDirection("Right") },
	{ key = "k", mods = "CMD|OPT", action = wezterm.action.ActivatePaneDirection("Up") },
	{ key = "j", mods = "CMD|OPT", action = wezterm.action.ActivatePaneDirection("Down") },

	-- Manage panes
	{ key = "w", mods = "CMD|SHIFT", action = wezterm.action.CloseCurrentPane({ confirm = true }) },
	{ key = "z", mods = "CMD|SHIFT", action = wezterm.action.TogglePaneZoomState },

	-- Resize panes
	{ key = "h", mods = "CMD|CTRL", action = wezterm.action.AdjustPaneSize({ "Left", 5 }) },
	{ key = "l", mods = "CMD|CTRL", action = wezterm.action.AdjustPaneSize({ "Right", 5 }) },
	{ key = "k", mods = "CMD|CTRL", action = wezterm.action.AdjustPaneSize({ "Up", 5 }) },
	{ key = "j", mods = "CMD|CTRL", action = wezterm.action.AdjustPaneSize({ "Down", 5 }) },
}

-- CTRL+ALT + number to move tab to that position
for i = 1, 8 do
	table.insert(config.keys, {
		key = tostring(i),
		mods = "CTRL|ALT",
		action = wezterm.action.MoveTab(i - 1),
	})
end

return config

--[[
  Popular color schemes to try:
  - "Tokyo Night"
  - "Catppuccin Mocha"
  - "Dracula"
  - "Gruvbox Dark"
  - "Nord"
  - "One Dark"
  - "Solarized Dark"
  - "Kanagawa"

  Run `wezterm ls-fonts --list-system` to see available fonts
  Full scheme list: https://wezfurlong.org/wezterm/colorschemes/index.html
]]
