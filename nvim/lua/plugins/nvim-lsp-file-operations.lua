---@type LazySpec
return {
  "antosha417/nvim-lsp-file-operations",
  -- Override astrocommunity config to prevent early init
  lazy = true,
  init = function() end, -- Override astrocommunity's init to prevent early astrocore loading
  event = "User AstroFile", -- Load with other LSP plugins
  dependencies = {
    "nvim-lua/plenary.nvim",
    {
      "AstroNvim/astrolsp",
      optional = true,
      opts = function(_, opts)
        if not opts.capabilities then opts.capabilities = {} end
        opts.capabilities.workspace = opts.capabilities.workspace or {}
        opts.capabilities.workspace.fileOperations = {
          didRename = true,
          willRename = true,
        }
      end,
    },
  },
  opts = {},
}
