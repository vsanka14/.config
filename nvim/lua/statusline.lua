local M = {}

-- ============================================================================
-- Mode labels and highlight mappings
-- ============================================================================
local mode_map = {
	n = "NORMAL",
	no = "OP-PENDING",
	nov = "OP-PENDING",
	noV = "OP-PENDING",
	["no\22"] = "OP-PENDING",
	niI = "NORMAL",
	niR = "NORMAL",
	niV = "NORMAL",
	nt = "NORMAL",
	v = "VISUAL",
	vs = "VISUAL",
	V = "VISUAL LINE",
	Vs = "VISUAL LINE",
	["\22"] = "VISUAL BLOCK",
	["\22s"] = "VISUAL BLOCK",
	s = "SELECT",
	S = "SELECT LINE",
	["\19"] = "SELECT BLOCK",
	i = "INSERT",
	ic = "INSERT",
	ix = "INSERT",
	R = "REPLACE",
	Rc = "REPLACE",
	Rx = "REPLACE",
	Rv = "VISUAL REPLACE",
	Rvc = "VISUAL REPLACE",
	Rvx = "VISUAL REPLACE",
	c = "COMMAND",
	cv = "EX",
	ce = "EX",
	r = "ENTER",
	rm = "MORE",
	["r?"] = "CONFIRM",
	["!"] = "SHELL",
	t = "TERMINAL",
}

local mode_hl = {
	NORMAL = "Mode",
	INSERT = "ModeInsert",
	VISUAL = "ModeVisual",
	["VISUAL LINE"] = "ModeVisual",
	["VISUAL BLOCK"] = "ModeVisual",
	SELECT = "ModeVisual",
	["SELECT LINE"] = "ModeVisual",
	["SELECT BLOCK"] = "ModeVisual",
	REPLACE = "ModeReplace",
	["VISUAL REPLACE"] = "ModeReplace",
	COMMAND = "ModeCommand",
	TERMINAL = "ModeTerm",
}

-- ============================================================================
-- Highlights (all prefixed with StatusLine internally)
-- ============================================================================
local hl_prefix = "StatusLine"

local hl_defs = {
	Mode = { fg = "#1a1b26", bg = "#7aa2f7", bold = true },
	ModeInsert = { fg = "#1a1b26", bg = "#9ece6a", bold = true },
	ModeVisual = { fg = "#1a1b26", bg = "#bb9af7", bold = true },
	ModeReplace = { fg = "#1a1b26", bg = "#f7768e", bold = true },
	ModeCommand = { fg = "#1a1b26", bg = "#e0af68", bold = true },
	ModeTerm = { fg = "#1a1b26", bg = "#7dcfff", bold = true },
	Macro = { fg = "#1a1b26", bg = "#f7768e", bold = true },
	File = { fg = "#c0caf5", bg = "#24283b", bold = true },
	Git = { fg = "#7aa2f7", bg = "#1a1b26" },
	GitIcon = { fg = "#e0af68", bg = "#1a1b26" },
	Search = { fg = "#1a1b26", bg = "#ff9e64", bold = true },
	PosIcon = { fg = "#7aa2f7", bg = "#24283b" },
	PosLine = { fg = "#c0caf5", bg = "#24283b" },
	PosSep = { fg = "#565f89", bg = "#24283b" },
	PosCol = { fg = "#9ece6a", bg = "#24283b" },
	PosPct = { fg = "#bb9af7", bg = "#24283b" },
	RdevSyncHealthy = { fg = "#9ece6a", bg = "#24283b" },
	RdevSyncWarn = { fg = "#e0af68", bg = "#24283b" },
	RdevSyncError = { fg = "#f7768e", bg = "#24283b" },
	RdevSyncMissing = { fg = "#565f89", bg = "#24283b" },
}

local function setup_highlights()
	for name, val in pairs(hl_defs) do
		vim.api.nvim_set_hl(0, hl_prefix .. name, val)
	end
end

--- Wrap text in statusline highlight
local function hl(name, text)
	return "%#" .. hl_prefix .. name .. "#" .. text .. "%*"
end

-- ============================================================================
-- Cached state (updated via autocmds, never computed in render)
-- ============================================================================
local cache = {
	git_branch = "",
	rdev_sync_hl = "RdevSyncMissing",
	rdev_sync_text = "",
}

local function update_git_branch()
	local dir = vim.fn.expand("%:p:h")
	if dir == "" then
		cache.git_branch = ""
		return
	end
	vim.fn.jobstart({ "git", "-C", dir, "rev-parse", "--abbrev-ref", "HEAD" }, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			cache.git_branch = (data and data[1] ~= "") and data[1] or ""
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				cache.git_branch = ""
			end
			vim.schedule(function()
				vim.cmd.redrawstatus()
			end)
		end,
	})
end

local rdev_sync_display = {
	healthy = "RdevSyncHealthy",
	syncing = "RdevSyncWarn",
	connecting = "RdevSyncWarn",
	paused = "RdevSyncError",
	disconnected = "RdevSyncError",
	["wrong-mode"] = "RdevSyncError",
	halted = "RdevSyncError",
	error = "RdevSyncError",
	missing = "RdevSyncMissing",
}

local function set_rdev_sync_status(category, name)
	local display = rdev_sync_display[category] or rdev_sync_display.error
	local label = name ~= "" and name or "sync error"
	local text = category == "missing" and "" or (" 󰍹 " .. label:gsub("%%", "%%%%") .. " ")

	if cache.rdev_sync_hl ~= display or cache.rdev_sync_text ~= text then
		cache.rdev_sync_hl = display
		cache.rdev_sync_text = text
		vim.cmd.redrawstatus()
	end
end

local function current_rdev_sync_path()
	local buffer_name = vim.api.nvim_buf_get_name(0)
	if buffer_name ~= "" and vim.bo.buftype == "" then
		local directory = vim.fs.dirname(buffer_name)
		if directory and vim.uv.fs_stat(directory) then
			return vim.uv.fs_realpath(directory) or directory
		end
	end

	local cwd = vim.fn.getcwd()
	return vim.uv.fs_realpath(cwd) or cwd
end

local rdev_sync_job
local requested_rdev_sync_path
local rdev_sync_stopping = false
local start_rdev_sync_job

start_rdev_sync_job = function(path)
	local output = {}
	local job = vim.fn.jobstart({ "rdev-info", "--sync-status", "--path", path }, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			output = data or {}
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				rdev_sync_job = nil
				if rdev_sync_stopping then
					return
				end

				if requested_rdev_sync_path == path then
					if code == 0 then
						local raw = table.concat(output, "\n")
						local ok, result = pcall(vim.json.decode, raw)
						if ok and type(result) == "table" then
							set_rdev_sync_status(result.category or "error", result.shortName or "")
						else
							set_rdev_sync_status("error", "")
						end
					else
						set_rdev_sync_status("error", "")
					end
				end

				if requested_rdev_sync_path ~= path then
					start_rdev_sync_job(requested_rdev_sync_path)
				end
			end)
		end,
	})

	if job <= 0 then
		set_rdev_sync_status("error", "")
		return
	end
	rdev_sync_job = job
end

local function update_rdev_sync_status()
	requested_rdev_sync_path = current_rdev_sync_path()
	if not rdev_sync_job then
		start_rdev_sync_job(requested_rdev_sync_path)
	end
end

-- ============================================================================
-- Autocmds
-- ============================================================================
local group = vim.api.nvim_create_augroup("statusline_cache", { clear = true })
local au = function(events, cb)
	vim.api.nvim_create_autocmd(events, { group = group, callback = cb })
end

au({ "BufEnter", "FocusGained", "DirChanged" }, update_git_branch)
au({ "BufEnter", "FocusGained", "DirChanged" }, update_rdev_sync_status)
au({ "RecordingEnter", "RecordingLeave" }, function()
	vim.cmd.redrawstatus()
end)

update_git_branch()
update_rdev_sync_status()

local rdev_sync_timer = vim.uv.new_timer()
rdev_sync_timer:start(5000, 5000, vim.schedule_wrap(update_rdev_sync_status))

au("VimLeavePre", function()
	rdev_sync_stopping = true
	if rdev_sync_job then
		vim.fn.jobstop(rdev_sync_job)
	end
	if not rdev_sync_timer:is_closing() then
		rdev_sync_timer:stop()
		rdev_sync_timer:close()
	end
end)

-- ============================================================================
-- Render (pure string concat, minimal API calls)
-- ============================================================================
function M.render()
	local mode = vim.api.nvim_get_mode().mode
	local mode_label = mode_map[mode] or mode

	-- Left: mode + search count + git
	local left = hl(mode_hl[mode_label] or "Mode", " " .. mode_label .. " ")

	-- Macro recording indicator
	local reg = vim.fn.reg_recording()
	if reg ~= "" then
		left = left .. hl("Macro", " REC @" .. reg .. " ")
	end

	-- Search match count (only when searching)
	if vim.v.hlsearch == 1 then
		local ok, sc = pcall(vim.fn.searchcount, { maxcount = 999 })
		if ok and sc.total and sc.total > 0 then
			left = left .. hl("Search", " \u{f002} " .. sc.current .. "/" .. sc.total .. " ")
		end
	end

	if cache.git_branch ~= "" then
		left = left .. hl("GitIcon", " \u{e725} ") .. hl("Git", cache.git_branch .. " ")
	end

	-- Right: rdev sync + position
	local right = ""

	local cur = vim.fn.line(".")
	local total = vim.fn.line("$")
	local pct = cur == 1 and "Top" or cur == total and "Bot" or (math.floor(cur / total * 100) .. "%%")
	right = right
		.. hl(cache.rdev_sync_hl, cache.rdev_sync_text)
		.. hl("PosIcon", " \u{f0c9} ")
		.. hl("PosLine", "%l")
		.. hl("PosSep", ":")
		.. hl("PosCol", "%c")
		.. hl("PosSep", " \u{f01e8} ")
		.. hl("PosPct", pct .. " ")

	return left .. "%=" .. right
end

-- ============================================================================
-- Init
-- ============================================================================
setup_highlights()
au("ColorScheme", setup_highlights)

vim.o.laststatus = 3
vim.o.statusline = "%!v:lua.require('statusline').render()"

return M
