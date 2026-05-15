return {
	"folke/zen-mode.nvim",
	cmd = "ZenMode",
	opts = {
		window = {
			backdrop = 0.95,
			width = 90,
			height = 1,
			options = {
				signcolumn = "no",
				number = false,
				relativenumber = false,
				cursorline = false,
				cursorcolumn = false,
				foldcolumn = "0",
				list = false,
			},
		},
		plugins = {
			options = {
				enabled = true,
				ruler = false,
				showcmd = false,
				laststatus = 0,
			},
		},
	},
}
