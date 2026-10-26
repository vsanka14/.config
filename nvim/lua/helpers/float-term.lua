local M = {}

--- Open a command in a centered floating terminal.
--- The float closes automatically when the command exits.
---@param cmd string The command to run
---@param opts? { width?: number, height?: number, border?: string, keep_open?: fun(code: integer): boolean, on_exit?: fun() }
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
			border = opts.border or "rounded",
		}
	end

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, window_config())
	vim.wo[win].winhighlight = "NormalFloat:Normal,FloatBorder:Normal"
	local resize_group = vim.api.nvim_create_augroup("FloatTermResize_" .. buf, { clear = true })

	vim.api.nvim_create_autocmd("VimResized", {
		group = resize_group,
		callback = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_set_config(win, window_config())
			end
		end,
	})

	local function close()
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
	end

	vim.fn.jobstart(cmd, {
		term = true,
		on_exit = function(_, code)
			if opts.keep_open and opts.keep_open(code) and vim.api.nvim_buf_is_valid(buf) then
				-- Leave the output visible until the user dismisses it.
				for _, key in ipairs({ "q", "<CR>", "<Esc>" }) do
					vim.keymap.set("n", key, close, { buffer = buf, nowait = true })
				end
				vim.api.nvim_echo({ { ("Exited with code %d. Press q to close."):format(code), "WarningMsg" } }, false, {})
				return
			end
			close()
		end,
	})
	vim.cmd("startinsert")
end

return M
