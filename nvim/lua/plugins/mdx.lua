-- MDX support configuration

---@type LazySpec
return {
  -- Mason: Install MDX language server
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "mdx-analyzer", -- MDX language server
      })
    end,
  },

  -- LSP: Configure mdx-analyzer
  {
    "AstroNvim/astrolsp",
    ---@type AstroLSPOpts
    opts = {
      config = {
        mdx_analyzer = {
          filetypes = { "mdx" },
        },
      },
    },
  },
}
