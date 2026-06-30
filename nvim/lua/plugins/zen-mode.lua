return {
	"folke/zen-mode.nvim",
	cmd = "ZenMode",
	opts = {
		window = {
			backdrop = 0.95,
			width = function()
				local ft = vim.bo.filetype
				if ft == "markdown" or ft == "markdown.mdx" then
					return 140
				end
				return 120
			end,
			height = 1,
			options = {
				signcolumn = "no",
				number = false,
				relativenumber = true,
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
