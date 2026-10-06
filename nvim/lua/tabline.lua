local M = {}
local zen = require("helpers.zen")

local sel_bg = "#1a1b26"
local fill_bg = "#050505"

-- Keep the MAX_BUFFERS most-recently-used saved files, plus every unsaved file;
-- unlist the rest so the tabline stays short. Unlisted buffers stay in memory
-- and reopen with :e / :b. Recency uses Neovim's own `lastused` timestamp, with
-- the current buffer pinned newest (it isn't stamped until you leave it).
local MAX_BUFFERS = 4

local function prune()
	local current = vim.api.nvim_get_current_buf()
	local files = vim.tbl_filter(function(info)
		return vim.bo[info.bufnr].buftype == ""
	end, vim.fn.getbufinfo({ buflisted = 1 }))

	table.sort(files, function(a, b)
		if a.bufnr == current or b.bufnr == current then
			return a.bufnr == current
		end
		if a.lastused ~= b.lastused then
			return a.lastused > b.lastused
		end
		return a.bufnr > b.bufnr
	end)

	local kept = 0
	for _, info in ipairs(files) do
		if info.changed ~= 1 then
			kept = kept + 1
			if kept > MAX_BUFFERS then
				vim.bo[info.bufnr].buflisted = false
			end
		end
	end
end

local function setup_highlights()
	vim.api.nvim_set_hl(0, "TabLineBuf", { fg = "#565f89", bg = fill_bg })
	vim.api.nvim_set_hl(0, "TabLineBufSel", { fg = "#c0caf5", bg = sel_bg })
	vim.api.nvim_set_hl(0, "TabLineMod", { fg = "#e0af68", bg = fill_bg })
	vim.api.nvim_set_hl(0, "TabLineModSel", { fg = "#e0af68", bg = sel_bg })
	vim.api.nvim_set_hl(0, "TabLineFill", { bg = fill_bg })
end

-- Cache for dynamically created icon highlight groups
local icon_hl_cache = {}

local function get_icon_hl(base_hl, is_sel)
	local suffix = is_sel and "_TabSel" or "_Tab"
	local hl_name = base_hl .. suffix

	if not icon_hl_cache[hl_name] then
		if is_sel then
			local existing = vim.api.nvim_get_hl(0, { name = base_hl, link = false })
			local fg = existing.fg
			if fg then
				vim.api.nvim_set_hl(0, hl_name, { fg = fg, bg = sel_bg })
			else
				vim.api.nvim_set_hl(0, hl_name, { link = base_hl })
			end
		else
			-- Dim inactive buffer icons to match the inactive text color
			local dim_fg = vim.api.nvim_get_hl(0, { name = "TabLineBuf", link = false }).fg
			vim.api.nvim_set_hl(0, hl_name, { fg = dim_fg, bg = fill_bg })
		end
		icon_hl_cache[hl_name] = true
	end

	return hl_name
end

function M.render()
	local bufs = vim.tbl_filter(function(b)
		return vim.bo[b].buflisted and vim.api.nvim_buf_is_loaded(b)
	end, vim.api.nvim_list_bufs())

	if #bufs == 0 then
		return ""
	end

	local has_mini, MiniIcons = pcall(require, "mini.icons")
	local current = vim.api.nvim_get_current_buf()
	local parts = {}

	for _, buf in ipairs(bufs) do
		local is_sel = buf == current
		local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
		if name == "" then
			name = "[No Name]"
		end

		-- Get icon + color from mini.icons
		local icon, icon_base_hl = "", "TabLineBuf"
		if has_mini and name ~= "[No Name]" then
			icon, icon_base_hl = MiniIcons.get("file", name)
		end

		local icon_hl = "%#" .. get_icon_hl(icon_base_hl, is_sel) .. "#"
		local buf_hl = is_sel and "%#TabLineBufSel#" or "%#TabLineBuf#"

		local mod_str = ""
		if vim.bo[buf].modified then
			local mod_hl = is_sel and "%#TabLineModSel#" or "%#TabLineMod#"
			mod_str = mod_hl .. " ⏺"
		end

		table.insert(parts, string.format("%%%dT%s %s %s%s%s %%T", buf, icon_hl, icon, buf_hl, name, mod_str))
	end

	return zen.tabline(table.concat(parts))
end

setup_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("tabline_colors", { clear = true }),
	callback = function()
		icon_hl_cache = {} -- Reset cache so highlights get recreated with new colors
		setup_highlights()
	end,
})

vim.api.nvim_create_autocmd("BufEnter", {
	group = vim.api.nvim_create_augroup("tabline_buffer_prune", { clear = true }),
	callback = prune,
	desc = "Unlist stale buffers so the tabline stays short",
})

vim.o.showtabline = 2
vim.o.tabline = "%!v:lua.require('tabline').render()"

return M
