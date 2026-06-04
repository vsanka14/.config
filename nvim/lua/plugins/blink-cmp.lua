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
			default = { "lsp", "path", "snippets", "buffer" },
			per_filetype = {
				markdown = {},
				mdx = {},
				text = {},
				-- Offline SQLite-backed dataset-name + column completion.
				sql = { "meta_columns", "lsp", "path", "snippets", "buffer" },
			},
			providers = {
				meta_columns = {
					name = "Meta",
					module = "blink-sources.meta_columns",
					-- The SQLite DB is built externally by ~/code/meta-gridtable-index/build_index.py.
					opts = {
						db_path = vim.fn.expand("~/.cache/meta-gridtable-index/index.sqlite3"),
						list_limit = 500,
					},
				},
			},
		},
	},
}
