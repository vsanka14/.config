return {
	"MeanderingProgrammer/render-markdown.nvim",
	dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" },
	ft = { "markdown", "markdown.mdx" },
	opts = {
		anti_conceal = {
			enabled = false,
		},
		win_options = {
			wrap = {
				rendered = false,
			},
			concealcursor = {
				rendered = "nc",
			},
		},
	},
}
