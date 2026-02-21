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
		},
		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
			per_filetype = {
				markdown = {},
				mdx = {},
				text = {},
			},
		},
		completion = {
			documentation = { auto_show = true },
		},
	},
}
