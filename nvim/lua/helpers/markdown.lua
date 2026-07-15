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

return M
