local M = {}

function M.jump()
	local bufs = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].buflisted then
			table.insert(bufs, buf)
		end
	end
	if #bufs == 0 then
		return
	end

	-- Assign hint characters based on filename
	local used = {}
	local hints = {}
	for _, buf in ipairs(bufs) do
		local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
		if name == "" then
			name = "[No Name]"
		end
		local hint = nil
		for i = 1, #name do
			local c = name:sub(i, i):lower()
			if c:match("[a-z]") and not used[c] then
				hint = c
				used[c] = true
				break
			end
		end
		if not hint then
			for i = 97, 122 do -- a-z
				local c = string.char(i)
				if not used[c] then
					hint = c
					used[c] = true
					break
				end
			end
		end
		hints[buf] = hint
	end

	-- Create bold highlight groups for hints
	local buf_hl = vim.api.nvim_get_hl(0, { name = "TabLineBuf", link = false })
	local buf_sel_hl = vim.api.nvim_get_hl(0, { name = "TabLineBufSel", link = false })
	vim.api.nvim_set_hl(0, "BufferJumpHint", { fg = buf_hl.fg, bg = buf_hl.bg, bold = true })
	vim.api.nvim_set_hl(0, "BufferJumpHintSel", { fg = buf_sel_hl.fg, bg = buf_sel_hl.bg, bold = true })

	-- Build tabline string
	local parts = {}
	for _, buf in ipairs(bufs) do
		local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
		if name == "" then
			name = "[No Name]"
		end
		local h = hints[buf] or "?"
		local is_current = buf == vim.api.nvim_get_current_buf()
		local hint_hl = is_current and "%#BufferJumpHintSel#" or "%#BufferJumpHint#"
		local text_hl = is_current and "%#TabLineBufSel#" or "%#TabLineBuf#"
		table.insert(parts, hint_hl .. " [" .. h .. "] " .. text_hl .. name .. " ")
	end
	local saved_tabline = vim.o.tabline
	vim.o.tabline = table.concat(parts) .. "%#TabLineFill#"
	vim.cmd("redrawtabline")

	-- Wait for keypress
	local ok, char = pcall(vim.fn.getcharstr)
	vim.o.tabline = saved_tabline
	vim.cmd("redrawtabline")

	if not ok then
		return
	end

	-- Find matching buffer
	for _, buf in ipairs(bufs) do
		if hints[buf] == char:lower() then
			vim.api.nvim_set_current_buf(buf)
			return
		end
	end
end

return M
