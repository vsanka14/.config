---@type LazySpec
return {
  "mikavilpas/yazi.nvim",
  version = "*", -- use the latest stable version
  event = "VeryLazy",
  dependencies = {
    { "nvim-lua/plenary.nvim", lazy = true },
  },
  keys = {
    {
      "<leader>e",
      "<cmd>Yazi<cr>",
      desc = "File Explorer (yazi)",
    },
  },
  ---@type YaziConfig | {}
  opts = {
    open_for_directories = true,
    keymaps = {
      show_help = "<f1>",
    },
  },
  init = function()
    -- Disable netrw so yazi handles directory opens
    vim.g.loaded_netrwPlugin = 1
  end,
}
