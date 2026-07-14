local M = {}

--- Open a command in a centered floating terminal.
--- The float closes automatically when the command exits.
---@param cmd string The command to run
---@param opts? { width?: number, height?: number, on_exit?: fun() }
function M.open(cmd, opts)
	opts = opts or {}
	local width_ratio = opts.width or 0.8
	local height_ratio = opts.height or 0.8

	local function window_config()
		local width = math.floor(vim.o.columns * width_ratio)
		local height = math.floor(vim.o.lines * height_ratio)

		return {
			relative = "editor",
			width = width,
			height = height,
			col = math.floor((vim.o.columns - width) / 2),
			row = math.floor((vim.o.lines - height) / 2),
			style = "minimal",
			border = "rounded",
		}
	end

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, window_config())
	local resize_group = vim.api.nvim_create_augroup("FloatTermResize_" .. buf, { clear = true })

	vim.api.nvim_create_autocmd("VimResized", {
		group = resize_group,
		callback = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_set_config(win, window_config())
			end
		end,
	})

	vim.fn.termopen(cmd, {
		on_exit = function()
			pcall(vim.api.nvim_del_augroup_by_id, resize_group)
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
			if opts.on_exit then
				vim.schedule(opts.on_exit)
			end
		end,
	})
	vim.cmd("startinsert")
end

return M
