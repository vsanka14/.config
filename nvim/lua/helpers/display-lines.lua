-- Display-line-relative numbers for wrapped filetypes (e.g. markdown).
-- Built-in relativenumber counts logical lines, but gj/gk move by display
-- lines — so the gutter lies when lines wrap. This uses screenpos() to give
-- each wrapped row its own relative number, making 3j land where "3" shows.
local M = {}

function M.statuscolumn()
	local virtnum = vim.v.virtnum
	if virtnum < 0 then return "" end

	local lnum = vim.v.lnum
	local pos = vim.fn.screenpos(0, lnum, 1)
	if pos.row == 0 then return "    " end

	local cursor_pos = vim.fn.screenpos(0, vim.fn.line("."), vim.fn.col("."))
	local screen_row = pos.row + virtnum
	local relnum = math.abs(screen_row - cursor_pos.row)

	if relnum == 0 then
		return string.format("%3d ", lnum)
	else
		return string.format("%3d ", relnum)
	end
end

return M
