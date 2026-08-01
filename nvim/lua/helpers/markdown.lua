local M = {}

--- Insert a fresh checkbox on the current line, keeping indent, then enter insert mode
function M.insert_checkbox()
	local line = vim.api.nvim_get_current_line()
	local indent = line:match("^%s*") or ""
	vim.api.nvim_set_current_line(indent .. "- [ ] ")
	vim.cmd("startinsert!")
end

--- Toggle the checkbox state on the current line between [ ] and [x]
function M.toggle_checkbox()
	local line = vim.api.nvim_get_current_line()
	if line:match("%[ %]") then
		line = line:gsub("%[ %]", "[x]", 1)
	elseif line:match("%[[xX]%]") then
		line = line:gsub("%[[xX]%]", "[ ]", 1)
	else
		return
	end
	vim.api.nvim_set_current_line(line)
end

--- Toggle the current checkbox, or insert a new checkbox below the current line
function M.toggle_or_insert_checkbox()
	local line = vim.api.nvim_get_current_line()
	if line:match("%[[ xX]%]") then
		M.toggle_checkbox()
		return
	end

	local indent = line:match("^%s*") or ""
	if line:match("^%s*$") then
		vim.api.nvim_set_current_line(indent .. "- [ ] ")
	else
		local row = vim.api.nvim_win_get_cursor(0)[1]
		vim.api.nvim_buf_set_lines(0, row, row, false, { indent .. "- [ ] " })
		vim.api.nvim_win_set_cursor(0, { row + 1, 6 + #indent })
	end
	vim.cmd("startinsert!")
end

return M
