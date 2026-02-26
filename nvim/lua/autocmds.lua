local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

-- Auto refresh buffer when file changes on disk
autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
	group = augroup("auto_refresh_buffer", { clear = true }),
	pattern = "*",
	callback = function()
		if vim.fn.getcmdwintype() == "" then
			vim.cmd.checktime()
		end
	end,
	desc = "Auto refresh buffer if file changed on disk",
})

-- Reapply italic highlights on colorscheme change
autocmd("ColorScheme", {
	group = augroup("italic_highlights", { clear = true }),
	callback = function()
		local comment_hl = vim.api.nvim_get_hl(0, { name = "Comment" })
		comment_hl.italic = true
		vim.api.nvim_set_hl(0, "Comment", comment_hl)

		local keyword_hl = vim.api.nvim_get_hl(0, { name = "Keyword" })
		keyword_hl.italic = true
		vim.api.nvim_set_hl(0, "Keyword", keyword_hl)
	end,
	desc = "Reapply italic highlights",
})

-- Markdown: wrap + display-line navigation so gutter numbers match gj/gk movement
autocmd("FileType", {
	group = augroup("markdown_settings", { clear = true }),
	pattern = { "markdown", "markdown.mdx" },
	callback = function(args)
		-- Trino result buffers use markdown filetype for table rendering but
		-- have wrap disabled, so display-line mappings (gj/gk/g0/g$) don't apply
		if vim.api.nvim_buf_get_name(args.buf):match("^trino://") then
			return
		end

		vim.opt_local.wrap = true
		vim.opt_local.linebreak = true
		vim.opt_local.conceallevel = 2
		vim.opt_local.concealcursor = "nc"
		vim.opt_local.statuscolumn = "%=%{v:lua.require('helpers.display-lines').statuscolumn()}"

		local opts = { buffer = true, silent = true }
		vim.keymap.set({ "n", "v", "o" }, "j", "gj", opts)
		vim.keymap.set({ "n", "v", "o" }, "k", "gk", opts)
		vim.keymap.set({ "n", "v" }, "0", "g0", opts)
		vim.keymap.set({ "n", "v" }, "$", "g$", opts)
	end,
	desc = "Markdown-specific options",
})

-- Glimmer unicode fix for .hbs files
local glimmer_group = augroup("glimmer_unicode_fix", { clear = true })

autocmd({ "BufReadPost", "BufNewFile" }, {
	group = glimmer_group,
	pattern = "*.hbs",
	callback = function(args)
		require("helpers.ember").convert_unicode_to_char(args.buf)
	end,
	desc = "Convert unicode escapes to chars on load",
})

autocmd("BufWritePre", {
	group = glimmer_group,
	pattern = "*.hbs",
	callback = function(args)
		require("helpers.ember").convert_char_to_unicode(args.buf)
	end,
	desc = "Convert chars back to unicode escapes on save",
})

autocmd("BufWritePost", {
	group = glimmer_group,
	pattern = "*.hbs",
	callback = function(args)
		require("helpers.ember").convert_unicode_to_char(args.buf)
	end,
	desc = "Restore buffer to treesitter-friendly state after save",
})

-- Inline git blame
local blame_group = augroup("inline_blame", { clear = true })
local blame = require("helpers.blame")

autocmd("CursorHold", {
	group = blame_group,
	callback = blame.show,
	desc = "Show inline git blame",
})

autocmd({ "CursorMoved", "InsertEnter" }, {
	group = blame_group,
	callback = function()
		blame.clear(vim.api.nvim_get_current_buf())
	end,
	desc = "Clear inline blame",
})

autocmd("BufDelete", {
	group = blame_group,
	callback = function(args)
		blame.clean_cache(args.buf)
	end,
	desc = "Clean blame cache",
})

-- Lazy-load Trino module on first SQL file
autocmd("FileType", {
	group = augroup("trino_setup", { clear = true }),
	pattern = "sql",
	once = true,
	callback = function()
		require("helpers.trino").setup({
			cluster = "holdem",
			headless_user = "convtrack",
			split_height_pct = 50,
		})
		vim.cmd("doautocmd FileType")
	end,
	desc = "Lazy-load Trino module on first SQL file",
})

-- Trino results: set filetype, insert empty lines for top and bottom borders, disable wrap
autocmd("BufWinEnter", {
	group = augroup("trino_results", { clear = true }),
	pattern = "trino://results/*",
	callback = function(args)
		local buf = args.buf
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "" })
		vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
		vim.bo[buf].modifiable = false
		vim.bo[buf].filetype = "markdown"
		vim.wo.wrap = false
	end,
	desc = "Prepare Trino result buffers for markdown rendering",
})

-- Highlight on yank
autocmd("TextYankPost", {
	group = augroup("highlight_yank", { clear = true }),
	callback = function()
		vim.hl.on_yank({ timeout = 200 })
	end,
	desc = "Highlight on yank",
})
