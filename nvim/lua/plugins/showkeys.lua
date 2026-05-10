return {
	"nvzone/showkeys",
	event = "VeryLazy",
	opts = {
		timeout = 1,
		maxkeys = 10,
		position = "bottom-right",
		winopts = {
			relative = "editor",
			style = "minimal",
			border = "double",
			height = 1,
			row = 1,
			col = 0,
			zindex = 100,
		},
		keyformat = {
			["<NL>"] = "<C-J>",
		},
	},
	config = function(_, opts)
		require("showkeys").setup(opts)
		vim.schedule(function()
			vim.cmd("ShowkeysToggle")
		end)
	end,
}
