return {
	"folke/tokyonight.nvim",
	lazy = false,
	priority = 1000,
	opts = {
		style = "night",
		transparent = true,
		terminal_colors = true,
		styles = {
			comments = { italic = true },
			keywords = { italic = true },
			functions = {},
			variables = {},
			sidebars = "transparent",
			floats = "dark",
		},
		sidebars = { "qf", "help", "terminal" },
		on_highlights = function(hl, c)
			hl.Whitespace = { fg = "#292e42" }
			hl.NonText = { fg = "#292e42" }
		end,
	},
	config = function(_, opts)
		require("tokyonight").setup(opts)
		vim.cmd.colorscheme("tokyonight")
	end,
}
