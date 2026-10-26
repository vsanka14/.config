local M = {}

local function relative_path()
	local path = vim.fn.expand("%:p")
	if path == "" then
		return ""
	end

	local root = vim.fs.root(path, { ".git" }) or vim.fn.getcwd()
	return vim.fs.relpath(root, path) or vim.fn.fnamemodify(path, ":.")
end

--- Copy file path to clipboard
function M.copy_path()
	local path = relative_path()
	vim.fn.setreg("+", path)
	vim.notify("Copied: " .. path, vim.log.levels.INFO)
end

--- Copy absolute file path to clipboard
function M.copy_abs_path()
	local path = vim.fn.expand("%:p")
	vim.fn.setreg("+", path)
	vim.notify("Copied: " .. path, vim.log.levels.INFO)
end

--- Copy file path with current line number to clipboard
function M.copy_path_line()
	local path = relative_path()
	local line = vim.fn.line(".")
	local result = path .. ":" .. line
	vim.fn.setreg("+", result)
	vim.notify("Copied: " .. result, vim.log.levels.INFO)
end

--- Copy file path with line range to clipboard (for visual mode)
function M.copy_path_lines()
	local path = relative_path()
	local start_line = vim.fn.line("v")
	local end_line = vim.fn.line(".")
	if start_line > end_line then
		start_line, end_line = end_line, start_line
	end
	local result = path .. ":" .. start_line .. "-" .. end_line
	vim.fn.setreg("+", result)
	vim.notify("Copied: " .. result, vim.log.levels.INFO)
end

return M
