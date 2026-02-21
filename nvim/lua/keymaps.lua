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

-- Buffer quick-jump by letter hint (a=1st, b=2nd, etc.)
map("n", "<Leader>bb", function()
	local bufs = vim.tbl_filter(function(b)
		return vim.bo[b].buflisted and vim.api.nvim_buf_is_loaded(b)
	end, vim.api.nvim_list_bufs())
	if #bufs == 0 then
		return
	end

	local labels = {}
	for i, b in ipairs(bufs) do
		local letter = string.char(96 + i) -- a, b, c, ...
		local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t")
		if name == "" then
			name = "[No Name]"
		end
		labels[letter] = b
		vim.api.nvim_echo({ { letter .. ": " .. name .. "  ", "Normal" } }, false, {})
	end
	vim.api.nvim_echo({ { "Jump to buffer: ", "Question" } }, false, {})

	local ok, char = pcall(vim.fn.getcharstr)
	vim.cmd("redraw")
	if ok and labels[char] then
		vim.api.nvim_set_current_buf(labels[char])
	end
end, { desc = "Jump to buffer by letter" })

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

-- Lazygit (opens in a floating terminal)
map("n", "<Leader>gg", function()
	vim.cmd("tabnew")
	vim.fn.termopen("lazygit", {
		on_exit = function()
			vim.cmd("tabclose")
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
