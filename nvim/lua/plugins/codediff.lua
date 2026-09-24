local function file_formatter(ctx)
	local layout = require("codediff.ui.explorer.formatters.file")(ctx)
	if require("helpers.diff-review").review_count(ctx.path) > 0 then
		table.insert(layout.right, 1, {
			segments = { { text = " ", hl = "DiffReviewSidebarBadge" } },
			truncate_priority = 4,
		})
	end
	return layout
end

return {
	"esmuellert/codediff.nvim",
	cmd = "CodeDiff",
	init = function()
		require("helpers.diff-review").setup()
	end,
	opts = {
		diff = {
			ignore_trim_whitespace = true,
			gutter_signs = {
				insert_text = "+",
				delete_text = "-",
				highlight_numbers = true,
				changed_priority = 100,
			},
		},
		explorer = {
			width = 46,
			view_mode = "tree",
			line_stats = {
				enabled = true,
				count_untracked = true,
			},
			formatters = {
				file = file_formatter,
			},
		},
		history = {
			height = 18,
			view_mode = "tree",
		},
		keymaps = {
			view = {
				next_hunk = "]d",
				prev_hunk = "[d",
			},
		},
	},
}
