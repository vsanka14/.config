local M = {}

local WIDTH = 120
local group = vim.api.nvim_create_augroup("native_zen", { clear = true })
local gutter_options = {
	"foldcolumn",
	"number",
	"numberwidth",
	"relativenumber",
	"signcolumn",
	"statuscolumn",
}
local state

local function valid(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function config(centered)
	local top = vim.o.showtabline == 0 and 0 or 1
	local bottom = vim.o.cmdheight + (vim.o.laststatus == 0 and 0 or 1)
	local height = math.max(1, vim.o.lines - top - bottom)
	local width = centered and math.max(1, math.min(WIDTH, vim.o.columns - 4)) or vim.o.columns

	return {
		relative = "editor",
		width = width,
		height = height,
		row = top,
		col = centered and math.floor((vim.o.columns - width) / 2) or 0,
		zindex = centered and 50 or 40,
	}
end

local function stop(sync)
	if not state then
		return
	end

	local active = state
	local buf
	local view
	state = nil
	vim.api.nvim_clear_autocmds({ group = group })

	if sync and valid(active.content) then
		buf = vim.api.nvim_win_get_buf(active.content)
		vim.api.nvim_set_current_win(active.content)
		view = vim.fn.winsaveview()
	end

	for _, win in ipairs({ active.content, active.backdrop }) do
		if valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	if valid(active.source) then
		if buf and vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_win_set_buf(active.source, buf)
		end
		vim.api.nvim_set_current_win(active.source)
		if view then
			vim.fn.winrestview(view)
		end
	end

	vim.cmd.redrawtabline()
end

local function resize()
	if not state or not valid(state.content) or not valid(state.backdrop) then
		stop(true)
		return
	end

	vim.api.nvim_win_set_config(state.backdrop, config(false))
	vim.api.nvim_win_set_config(state.content, config(true))
end

function M.column()
	return state and config(true).col
end

function M.is_active()
	return state ~= nil
end

function M.tabline(content)
	local column = M.column()
	local padding = column and string.rep(" ", column) or ""
	return "%#TabLineFill#" .. padding .. content .. "%#TabLineFill#%="
end

function M.toggle()
	if state then
		stop(true)
		return
	end

	local source = vim.api.nvim_get_current_win()
	local view = vim.fn.winsaveview()
	local gutter = {}
	for _, option in ipairs(gutter_options) do
		gutter[option] = vim.api.nvim_get_option_value(option, { win = source })
	end

	local backdrop_buf = vim.api.nvim_create_buf(false, true)
	local backdrop = vim.api.nvim_open_win(backdrop_buf, false, config(false))
	vim.bo[backdrop_buf].bufhidden = "wipe"
	vim.wo[backdrop].foldcolumn = "0"
	vim.wo[backdrop].number = false
	vim.wo[backdrop].relativenumber = false
	vim.wo[backdrop].signcolumn = "no"
	vim.wo[backdrop].statuscolumn = ""
	vim.wo[backdrop].fillchars = "eob: "
	vim.wo[backdrop].winhighlight = "Normal:Normal,EndOfBuffer:Normal"

	local content = vim.api.nvim_open_win(vim.api.nvim_get_current_buf(), true, config(true))
	for option, value in pairs(gutter) do
		vim.api.nvim_set_option_value(option, value, { win = content })
	end

	local winhighlight = vim.api.nvim_get_option_value("winhighlight", { win = source })
	local transparent = "NormalFloat:Normal,FloatBorder:Normal"
	vim.wo[content].winhighlight = winhighlight == "" and transparent or winhighlight .. "," .. transparent
	vim.fn.winrestview(view)

	state = { source = source, backdrop = backdrop, content = content }
	require("helpers.blame").clear(vim.api.nvim_get_current_buf())

	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = resize,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(event)
			if state and (tonumber(event.match) == state.content or tonumber(event.match) == state.backdrop) then
				stop(true)
			end
		end,
	})

	vim.cmd.redrawtabline()
end

vim.api.nvim_create_user_command("Zen", M.toggle, {})

return M
