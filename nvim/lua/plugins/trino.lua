return {
	dir = vim.fn.expand("~/code/trino.nvim"),
	dev = true,
	ft = "sql",
	cmd = { "TrinoRun", "TrinoCluster", "TrinoCancel", "TrinoHeadlessUser", "TrinoNext", "TrinoPrev" },
	opts = {
		cluster = "holdem",
		headless_user = "convtrack",
		split_height_pct = 50,
	},
	config = function(_, opts)
		require("trino").setup(opts)
	end,
}
