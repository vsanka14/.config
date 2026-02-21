return {
	"echasnovski/mini.nvim",
	lazy = false,
	config = function()
		-- Fuzzy picker
		require("mini.pick").setup({
			mappings = {
				move_down = "<C-j>",
				move_up = "<C-k>",
				mark = "<C-s>", -- toggle mark on current item
				mark_all = "<C-a>", -- toggle mark on all matches
				choose_marked = "<C-x>", -- send marked to quickfix
			},
			window = {
				config = function()
					local height = math.floor(0.6 * vim.o.lines)
					local width = math.floor(0.6 * vim.o.columns)
					return {
						anchor = "NW",
						height = height,
						width = width,
						row = math.floor((vim.o.lines - height) / 2 - 1),
						col = math.floor((vim.o.columns - width) / 2),
					}
				end,
			},
		})

		-- Notifications
		require("mini.notify").setup({
			lsp_progress = { enable = false },
			window = {
				max_width_share = 0.4,
			},
		})
		vim.notify = require("mini.notify").make_notify()

		-- Highlight word under cursor
		require("mini.cursorword").setup()

		-- Auto pairs
		require("mini.pairs").setup()

		-- Icons
		require("mini.icons").setup({
			extension = {
				astro = { glyph = "\u{f1cde}", hl = "MiniIconsOrange" },
				mdx = { glyph = "\u{f0354}", hl = "MiniIconsAzure" },
				hbs = { glyph = "\u{e60f}", hl = "MiniIconsOrange" },
			},
		})

		-- Git diff (gutter signs + overlay)
		require("mini.diff").setup({
			view = {
				style = "sign",
				signs = { add = "+", change = "~", delete = "_" },
			},
		})
	end,
}
