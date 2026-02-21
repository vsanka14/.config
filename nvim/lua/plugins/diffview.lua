return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
  keys = {
    { "<Leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Git diff view" },
    { "<Leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File git history" },
    { "<Leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Branch git history" },
    { "<Leader>gx", "<cmd>DiffviewClose<cr>", desc = "Close diff view" },
  },
  opts = {
    enhanced_diff_hl = true,
    view = {
      merge_tool = {
        layout = "diff3_mixed",
      },
    },
  },
}
