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
				-- meta-backed dataset-name + column completion alongside SQL sources.
				sql = { "meta_columns", "lsp", "path", "snippets", "buffer" },
			},
			providers = {
				meta_columns = {
					name = "Meta",
					module = "blink-sources.meta_columns",
					-- Show other sources immediately; stream meta results in as
					-- the async fetches resolve.
					async = true,
					opts = {
						platform = "gridTable",
					},
				},
			},
		},
	},
}
