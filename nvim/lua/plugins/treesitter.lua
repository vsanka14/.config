local parsers = {
	"astro",
	"bash",
	"css",
	"diff",
	"git_config",
	"git_rebase",
	"gitcommit",
	"gitignore",
	"glimmer",
	"groovy",
	"html",
	"java",
	"javascript",
	"jsdoc",
	"json",
	"kusto",
	"lua",
	"luap",
	"markdown",
	"markdown_inline",
	"properties",
	"python",
	"scss",
	"sql",
	"svelte",
	"toml",
	"tsx",
	"typescript",
	"vim",
	"vimdoc",
	"xml",
	"yaml",
}

local select_maps = {
	["af"] = "@function.outer",
	["if"] = "@function.inner",
	["ac"] = "@class.outer",
	["ic"] = "@class.inner",
	["aa"] = "@parameter.outer",
	["ia"] = "@parameter.inner",
}

local move_maps = {
	["]f"] = { "goto_next_start", "@function.outer" },
	["]c"] = { "goto_next_start", "@class.outer" },
	["[f"] = { "goto_previous_start", "@function.outer" },
	["[c"] = { "goto_previous_start", "@class.outer" },
}

-- Textobject maps are buffer-local and only set where a textobjects query
-- exists, as the master branch did, so other buffers keep native ]c/[c etc.
local function map_textobjects(buf)
	for lhs, capture in pairs(select_maps) do
		vim.keymap.set({ "x", "o" }, lhs, function()
			require("nvim-treesitter-textobjects.select").select_textobject(capture, "textobjects")
		end, { buffer = buf, desc = "Select " .. capture })
	end
	for lhs, spec in pairs(move_maps) do
		local fn, capture = spec[1], spec[2]
		vim.keymap.set({ "n", "x", "o" }, lhs, function()
			require("nvim-treesitter-textobjects.move")[fn](capture, "textobjects")
		end, { buffer = buf, desc = fn .. " " .. capture })
	end
end

-- Replaces master's highlight/indent modules: enable per buffer only when the
-- parser and the matching query are available.
local function attach(args)
	local lang = vim.treesitter.language.get_lang(args.match)
	local ok, added = pcall(vim.treesitter.language.add, lang or "")
	if not lang or not ok or not added then
		return
	end
	local query = vim.treesitter.query
	if query.get(lang, "highlights") then
		pcall(vim.treesitter.start, args.buf, lang)
	end
	if query.get(lang, "indents") then
		vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end
	if query.get(lang, "textobjects") then
		map_textobjects(args.buf)
	end
end

return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		build = ":TSUpdate",
		config = function()
			require("nvim-treesitter").install(parsers)
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("treesitter_attach", { clear = true }),
				callback = attach,
				desc = "Enable treesitter highlight, indent and textobjects",
			})
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		branch = "main",
		lazy = false,
		config = function()
			require("nvim-treesitter-textobjects").setup({
				select = { lookahead = true },
				move = { set_jumps = true },
			})
		end,
	},
	{
		"windwp/nvim-ts-autotag",
		event = { "BufReadPost", "BufNewFile" },
		opts = {},
	},
}
