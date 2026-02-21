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
	local current = vim.api.nvim_get_current_buf()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if buf ~= current and vim.bo[buf].buflisted then
			vim.api.nvim_buf_delete(buf, {})
		end
	end
end, { desc = "Close other buffers" })
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

-- Diffview
map("n", "<Leader>gd", "<cmd>DiffviewOpen<cr>", { desc = "Git diff view" })
map("n", "<Leader>gh", "<cmd>DiffviewFileHistory %<cr>", { desc = "File git history" })
map("n", "<Leader>gH", "<cmd>DiffviewFileHistory<cr>", { desc = "Branch git history" })
map("n", "<Leader>gx", "<cmd>DiffviewClose<cr>", { desc = "Close diff view" })

-- Lazygit
map("n", "<Leader>gg", function()
	require("helpers.float-term").open("lazygit")
end, { desc = "Open Lazygit" })

-- Yazi file explorer
map("n", "<Leader>e", function()
	local chooser_file = vim.fn.tempname()
	local cmd = string.format("yazi --chooser-file=%s %s", chooser_file, vim.fn.expand("%:p:h"))
	require("helpers.float-term").open(cmd, {
		width = 0.85,
		height = 0.85,
		on_exit = function()
			local f = io.open(chooser_file, "r")
			if f then
				local path = f:read("*l")
				f:close()
				vim.fn.delete(chooser_file)
				if path and path ~= "" then
					vim.cmd("edit " .. vim.fn.fnameescape(path))
				end
			end
		end,
	})
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

-- DAP (debug adapter)
map("n", "<Leader>db", function()
	require("dap").toggle_breakpoint()
end, { desc = "Toggle breakpoint" })
map("n", "<Leader>dc", function()
	require("dap").continue()
end, { desc = "Continue" })
map("n", "<Leader>di", function()
	require("dap").step_into()
end, { desc = "Step into" })
map("n", "<Leader>do", function()
	require("dap").step_over()
end, { desc = "Step over" })
map("n", "<Leader>dO", function()
	require("dap").step_out()
end, { desc = "Step out" })
map("n", "<Leader>dr", function()
	require("dap").repl.open()
end, { desc = "Open REPL" })
map("n", "<Leader>dt", function()
	require("dap").terminate()
end, { desc = "Terminate" })
map("n", "<Leader>du", function()
	require("dapui").toggle()
end, { desc = "Toggle DAP UI" })

-- Clear search highlights
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear highlights" })
