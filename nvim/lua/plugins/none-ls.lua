-- Customize None-ls sources (linters)
-- Note: ESLint is now handled via eslint-lsp instead of none-ls

---@type LazySpec
return {
  "nvimtools/none-ls.nvim",
  opts = function(_, opts)
    -- Add additional none-ls sources here if needed
    -- ESLint has been moved to eslint-lsp for better compatibility
  end,
}
