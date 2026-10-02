return {
	"saghen/blink.cmp",
	event = "InsertEnter",
	version = "*",
	opts = {
		keymap = {
			preset = "default",
			["<C-j>"] = { "select_next", "fallback" },
			["<C-k>"] = { "select_prev", "fallback" },
			["<C-l>"] = { "accept", "fallback" },
			["<CR>"] = { "accept", "fallback" },
		},
		sources = {
			default = { "lsp", "path", "snippets", "buffer", "tags" },
			per_filetype = {
				markdown = {},
				mdx = {},
				text = {},
				-- Offline SQLite-backed dataset-name + column completion.
				sql = { "gridtable", "lsp", "path", "snippets", "buffer" },
			},
			providers = {
				gridtable = {
					name = "GridTable",
					module = "helpers.gridtable",
					-- The SQLite DB is built externally by ~/code/meta-gridtable-index/build_index.py.
					opts = {
						db_path = vim.fn.expand("~/.cache/meta-gridtable-index/index.sqlite3"),
						list_limit = 500,
					},
				},
				-- Cross-file symbol completion from the ctags index (no LSP needed).
				tags = {
					name = "Tags",
					module = "helpers.tags_source",
					min_keyword_length = 3,
					-- Rank below lsp/snippets/buffer so semantic/local results win.
					score_offset = -3,
					opts = {
						min_keyword = 3,
						list_limit = 200,
					},
				},
			},
		},
	},
}
