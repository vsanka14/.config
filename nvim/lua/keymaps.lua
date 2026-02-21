local map = vim.keymap.set

-- Save
map({ "n", "i", "v" }, "<C-s>", "<cmd>write<cr>", { desc = "Save file" })

-- Redo with U
map("n", "U", "<C-r>", { desc = "Redo" })

-- Centered scrolling
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down (centered)" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up (centered)" })
map("n", "<C-f>", "<C-f>zz", { desc = "Page down (centered)" })
map("n", "<C-b>", "<C-b>zz", { desc = "Page up (centered)" })

-- Buffer navigation
map("n", "<Leader>bn", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<Leader>bp", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
map("n", "<Leader>bc", function()
	local buf = vim.api.nvim_get_current_buf()
	vim.cmd("bprevious")
	vim.api.nvim_buf_delete(buf, {})
end, { desc = "Close buffer" })
map("n", "<Leader>c", function()
	local buf = vim.api.nvim_get_current_buf()
	vim.cmd("bprevious")
	vim.api.nvim_buf_delete(buf, {})
end, { desc = "Close buffer" })

-- Git keymaps (using mini.diff where applicable)
map("n", "<Leader>g", "<nop>", { desc = "Git" })
map("n", "<Leader>gp", function()
	MiniDiff.toggle_overlay(0)
end, { desc = "Toggle diff overlay" })
map("n", "<Leader>gr", function()
	MiniDiff.do_hunks(0, "reset")
end, { desc = "Reset hunk" })
map("n", "<Leader>gR", function()
	MiniDiff.do_hunks(0, "reset", { line_start = 1, line_end = vim.fn.line("$") })
end, { desc = "Reset buffer" })
map("v", "<Leader>gr", function()
	MiniDiff.do_hunks(0, "reset")
end, { desc = "Reset selected hunk" })
map("n", "]h", function()
	MiniDiff.goto_hunk("next")
end, { desc = "Next git hunk" })
map("n", "[h", function()
	MiniDiff.goto_hunk("prev")
end, { desc = "Previous git hunk" })

-- Lazygit (floating terminal inside Neovim)
map("n", "<Leader>gg", function()
	local buf = vim.api.nvim_create_buf(false, true)
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
	})
	vim.fn.termopen("lazygit", {
		on_exit = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end,
	})
	vim.cmd("startinsert")
end, { desc = "Open Lazygit" })

-- Yazi file explorer
map("n", "<Leader>e", function()
	require("helpers.yazi").open()
end, { desc = "File Explorer (yazi)" })

-- Yank helpers
map("n", "<Leader>ac", function()
	require("helpers.yank").copy_path_line()
end, { desc = "Copy file path:line" })
map("v", "<Leader>ac", function()
	require("helpers.yank").copy_path_lines()
end, { desc = "Copy file path:lines" })
map("n", "<Leader>ad", function()
	require("helpers.yank").copy_diagnostic()
end, { desc = "Copy diagnostic" })

-- Ember helpers
map("n", "<Leader>oa", function()
	require("helpers.ember").go_to_alternate()
end, { desc = "Alternate Ember file" })
map("n", "<Leader>ot", function()
	require("helpers.ember").open_test()
end, { desc = "Open Ember test" })
map("n", "<Leader>os", function()
	require("helpers.ember").open_source()
end, { desc = "Open source from test" })
map("n", "<Leader>yt", function()
	require("helpers.ember").copy_test_module()
end, { desc = "Yank test module name" })

-- Mini.pick keymaps
map("n", "<Leader>ff", function()
	MiniPick.builtin.files()
end, { desc = "Find files" })
map("n", "<Leader>fw", function()
	MiniPick.builtin.grep_live()
end, { desc = "Live grep" })
map("n", "<Leader>fb", function()
	MiniPick.builtin.buffers()
end, { desc = "Find buffers" })
map("n", "<Leader>fh", function()
	MiniPick.builtin.help()
end, { desc = "Find help" })
map("n", "<Leader>fd", function()
	local items = {}
	for _, d in ipairs(vim.diagnostic.get(nil)) do
		local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(d.bufnr), ":~:.")
		local severity = vim.diagnostic.severity[d.severity]
		table.insert(items, {
			text = string.format("%s:%d:%d [%s] %s", fname, d.lnum + 1, d.col + 1, severity, d.message),
			bufnr = d.bufnr,
			lnum = d.lnum + 1,
			col = d.col + 1,
		})
	end
	MiniPick.start({
		source = {
			name = "Diagnostics",
			items = items,
			choose = function(item)
				vim.api.nvim_set_current_buf(item.bufnr)
				vim.api.nvim_win_set_cursor(0, { item.lnum, item.col - 1 })
			end,
		},
	})
end, { desc = "Find diagnostics" })

map("n", "<Leader>fs", function()
	local params = { query = "" }
	vim.lsp.buf_request(0, "textDocument/documentSymbol", {
		textDocument = vim.lsp.util.make_text_document_params(),
	}, function(err, result)
		if err or not result then
			return
		end
		local items = {}
		local function flatten(symbols, prefix)
			for _, s in ipairs(symbols) do
				local name = prefix ~= "" and (prefix .. "." .. s.name) or s.name
				table.insert(items, {
					text = string.format(
						"[%s] %s :%d",
						vim.lsp.protocol.SymbolKind[s.kind] or "?",
						name,
						s.range.start.line + 1
					),
					lnum = s.range.start.line + 1,
					col = s.range.start.character + 1,
				})
				if s.children then
					flatten(s.children, name)
				end
			end
		end
		flatten(result, "")
		MiniPick.start({
			source = {
				name = "Document Symbols",
				items = items,
				choose = function(item)
					vim.api.nvim_win_set_cursor(0, { item.lnum, item.col - 1 })
				end,
			},
		})
	end)
end, { desc = "Find LSP symbols" })

-- Completion navigation
map("i", "<C-j>", "<C-n>", { desc = "Next completion item" })
map("i", "<C-k>", "<C-p>", { desc = "Previous completion item" })

-- Clear search highlights
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear highlights" })
