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
	File = { fg = "#c0caf5", bg = "#24283b", bold = true },
	Git = { fg = "#7aa2f7", bg = "#1a1b26" },
	GitIcon = { fg = "#e0af68", bg = "#1a1b26" },
	DiagError = { fg = "#f7768e", bg = "#1a1b26" },
	DiagWarn = { fg = "#e0af68", bg = "#1a1b26" },
	DiagInfo = { fg = "#7dcfff", bg = "#1a1b26" },
	DiagHint = { fg = "#9ece6a", bg = "#1a1b26" },
	Lsp = { fg = "#565f89", bg = "#1a1b26" },
	Search = { fg = "#1a1b26", bg = "#ff9e64", bold = true },
	PosIcon = { fg = "#7aa2f7", bg = "#24283b" },
	PosLine = { fg = "#c0caf5", bg = "#24283b" },
	PosSep = { fg = "#565f89", bg = "#24283b" },
	PosCol = { fg = "#9ece6a", bg = "#24283b" },
	PosPct = { fg = "#bb9af7", bg = "#24283b" },
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
local cache = { git_branch = "", lsp_progress = "", lsp_clients = "", diag = "" }

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
		end,
	})
end

local diag_icons = {
	{ vim.diagnostic.severity.ERROR, "DiagError", "\u{f0674} " },
	{ vim.diagnostic.severity.WARN, "DiagWarn", "\u{f0026} " },
	{ vim.diagnostic.severity.INFO, "DiagInfo", "\u{f02fc} " },
	{ vim.diagnostic.severity.HINT, "DiagHint", "\u{f0835} " },
}

local function update_diagnostics()
	local parts = {}
	for _, d in ipairs(diag_icons) do
		local count = #vim.diagnostic.get(0, { severity = d[1] })
		if count > 0 then
			parts[#parts + 1] = hl(d[2], d[3] .. count .. " ")
		end
	end
	cache.diag = table.concat(parts)
end

local function update_lsp_clients()
	local clients = vim.lsp.get_clients({ bufnr = 0 })
	if #clients > 0 then
		local names = {}
		for _, c in ipairs(clients) do
			names[#names + 1] = c.name
		end
		cache.lsp_clients = table.concat(names, ", ")
	else
		cache.lsp_clients = ""
	end
end

local lsp_progress_map = {}

local function update_lsp_progress(args)
	local data = args.data
	if not data or not data.params then
		return
	end
	local val = data.params.value
	local id = data.client_id
	if not val or not id then
		return
	end

	if val.kind == "end" then
		lsp_progress_map[id] = nil
	else
		local msg = val.title or ""
		if val.message then
			msg = msg .. ": " .. val.message
		end
		if val.percentage then
			msg = msg .. " (" .. val.percentage .. "%%%%)"
		end
		lsp_progress_map[id] = msg
	end

	local msgs = {}
	for _, msg in pairs(lsp_progress_map) do
		msgs[#msgs + 1] = msg
	end
	cache.lsp_progress = table.concat(msgs, " | ")
end

-- ============================================================================
-- Autocmds
-- ============================================================================
local group = vim.api.nvim_create_augroup("statusline_cache", { clear = true })
local au = function(events, cb)
	vim.api.nvim_create_autocmd(events, { group = group, callback = cb })
end

au({ "BufEnter", "FocusGained", "DirChanged" }, update_git_branch)
au("DiagnosticChanged", update_diagnostics)
au({ "LspAttach", "LspDetach", "BufEnter" }, update_lsp_clients)
au("LspProgress", update_lsp_progress)

update_git_branch()

-- ============================================================================
-- Render (pure string concat, minimal API calls)
-- ============================================================================
function M.render()
	local mode = vim.api.nvim_get_mode().mode
	local mode_label = mode_map[mode] or mode

	-- Left: mode + search count + git
	local left = hl(mode_hl[mode_label] or "Mode", " " .. mode_label .. " ")

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

	-- Right: diagnostics + lsp + position
	local right = cache.diag
	if cache.lsp_progress ~= "" then
		right = right .. hl("Lsp", " " .. cache.lsp_progress .. " ")
	elseif cache.lsp_clients ~= "" then
		right = right .. hl("Lsp", " " .. cache.lsp_clients .. " ")
	end

	local cur = vim.fn.line(".")
	local total = vim.fn.line("$")
	local pct = cur == 1 and "Top" or cur == total and "Bot" or (math.floor(cur / total * 100) .. "%%")
	right = right
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
