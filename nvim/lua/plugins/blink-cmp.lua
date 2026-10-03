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
		-- Surface exact/prefix matches first, then the Rust matcher's score
		-- (already boosted by proximity + frecency) orders the rest.
		fuzzy = {
			sorts = { "exact", "score", "sort_text" },
		},
		sources = {
			default = { "path", "snippets", "buffer", "tags" },
			per_filetype = {
				markdown = {},
				mdx = {},
				text = {},
				-- Offline SQLite-backed dataset-name + column completion.
				sql = { "gridtable", "path", "snippets", "buffer" },
			},
			providers = {
				-- Drop buffer words that are already indexed as tags so the tags
				-- provider owns them (correct kind/icon) instead of showing a dupe.
				buffer = {
					transform_items = function(_, items)
						local col = vim.api.nvim_win_get_cursor(0)[2]
						local before = vim.api.nvim_get_current_line():sub(1, col)
						local prefix = before:match("[%w_]+$")
						if not prefix or #prefix < 4 then
							return items
						end
						local ok, src = pcall(require, "helpers.tags_source")
						if not ok then
							return items
						end
						local is_tag = {}
						for _, t in ipairs(src.query_prefix(prefix)) do
							is_tag[t.name] = true
						end
						return vim.tbl_filter(function(it)
							return not is_tag[it.label]
						end, items)
					end,
				},
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
					min_keyword_length = 4,
					-- Above buffer (-3): with LSP off, tags is the symbol authority,
					-- so its items win dedupe and show the right kind/icon.
					score_offset = 0,
					opts = {
						min_keyword = 4,
						list_limit = 200,
					},
				},
			},
		},
	},
}
