return {
	"linkedin-managed/trino.nvim",
	url = "git@github.com:linkedin-managed/trino.nvim.git",
	enabled = false, -- Work-only private plugin; disabled on the personal machine.
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
