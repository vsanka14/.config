-- Customize Mason
-- NOTE: Language servers are handled by community packs (lua, typescript, astro, mdx)

---@type LazySpec
return {
  -- use mason-tool-installer for automatically installing Mason packages
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    -- overrides `require("mason-tool-installer").setup(...)`
    opts = {
      -- Make sure to use the names found in `:Mason`
      ensure_installed = {
        -- formatters
        "stylua",
        "prettier",
        "sql-formatter",

        -- linters
        "eslint-lsp",

        -- utilities
        "tree-sitter-cli",
      },
    },
  },
}
