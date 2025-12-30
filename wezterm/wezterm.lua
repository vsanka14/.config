local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Custom vibrant color scheme for terminal text only
config.colors = {
	-- Foreground and background
	foreground = "#A0FFFF", -- Light cyan text
	background = "#000000", -- Deep black background

	-- Cursor (subtle)
	cursor_bg = "#FFFFFF", -- White cursor
	cursor_fg = "#000000", -- Black cursor text
	cursor_border = "#FFFFFF",

	-- Selection (subtle)
	selection_bg = "#444444", -- Dark gray selection
	selection_fg = "#FFFFFF", -- White selection text

	-- ANSI colors (normal) - These make your ls output and text colorful!
	ansi = {
		"#2E3440", -- black
		"#FF6B9D", -- red (hot pink variant) - for errors, etc.
		"#32CD32", -- green (lime green) - for executable files
		"#FFD700", -- yellow (gold) - for directories and warnings
		"#87CEEB", -- blue (sky blue) - for links and info
		"#FF69B4", -- magenta (hot pink) - for special files
		"#00FFFF", -- cyan (bright cyan) - for other file types
		"#FFFFFF", -- white - for regular text
	},

	-- ANSI colors (bright) - Even more vibrant versions
	brights = {
		"#4C566A", -- bright black
		"#FF8FA3", -- bright red (lighter hot pink)
		"#7FFF00", -- bright green (chartreuse)
		"#FFFF00", -- bright yellow (pure yellow)
		"#00BFFF", -- bright blue (deep sky blue)
		"#FF1493", -- bright magenta (deep pink)
		"#00FFFF", -- bright cyan (aqua)
		"#FFFFFF", -- bright white
	},
}

-- Custom tab title formatting for clear borders
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local background = "#1a1a1a"
	local foreground = "#A0FFFF"
	local edge_foreground = "#444444" -- Color for the vertical separator

	if tab.is_active then
		background = "#00FFFF"
		foreground = "#000000"
	elseif hover then
		background = "#333333"
		foreground = "#FFFFFF"
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

-- Background image and transparency
config.background = {
	{
		source = {
			File = "/Users/vasishtshankar/Documents/pics/tokyo-coffee-shop.png",
		},
		-- The background image will be scaled to fill the window
		width = "100%",
		height = "100%",
		opacity = 1.0, -- Fully opaque image
		-- Further dim the image
		hsb = { brightness = 0.04 },
	},
	-- Overlays a darker semi-transparent gradient to improve contrast
}
config.window_background_opacity = 1.0 -- Fully opaque window - no additional transparency
config.macos_window_background_blur = 0 -- No blur at all - crisp, clear image
config.text_background_opacity = 1.0 -- Ensure text background is opaque

-- Font
config.font = wezterm.font("JetBrains Mono", { weight = "Bold" })
config.font_size = 15.0

-- Window
config.window_decorations = "TITLE | RESIZE" -- Native macOS title bar with traffic light buttons
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
	{ key = "k", mods = "CMD", action = wezterm.action.ClearScrollback("ScrollbackAndViewport") },
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
	{ key = "|", mods = "CMD|SHIFT", action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "_", mods = "CMD|SHIFT", action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }) },

	-- Navigate panes
	{ key = "LeftArrow", mods = "CMD|OPT", action = wezterm.action.ActivatePaneDirection("Left") },
	{ key = "RightArrow", mods = "CMD|OPT", action = wezterm.action.ActivatePaneDirection("Right") },
	{ key = "UpArrow", mods = "CMD|OPT", action = wezterm.action.ActivatePaneDirection("Up") },
	{ key = "DownArrow", mods = "CMD|OPT", action = wezterm.action.ActivatePaneDirection("Down") },

	-- Manage panes
	{ key = "w", mods = "CMD|SHIFT", action = wezterm.action.CloseCurrentPane({ confirm = true }) },
	{ key = "z", mods = "CMD|SHIFT", action = wezterm.action.TogglePaneZoomState },

	-- Resize panes
	{ key = "LeftArrow", mods = "CMD|CTRL", action = wezterm.action.AdjustPaneSize({ "Left", 5 }) },
	{ key = "RightArrow", mods = "CMD|CTRL", action = wezterm.action.AdjustPaneSize({ "Right", 5 }) },
	{ key = "UpArrow", mods = "CMD|CTRL", action = wezterm.action.AdjustPaneSize({ "Up", 5 }) },
	{ key = "DownArrow", mods = "CMD|CTRL", action = wezterm.action.AdjustPaneSize({ "Down", 5 }) },
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
