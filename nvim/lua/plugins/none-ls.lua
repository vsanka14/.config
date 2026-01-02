-- Customize None-ls sources (linters)
-- Note: ESLint is now handled via eslint-lsp instead of none-ls
-- DISABLED: none-ls.nvim is incompatible with Neovim 0.11
-- Formatting is handled by conform.nvim (see plugins/conform.lua)
-- If you need linters, consider using nvim-lint or other alternatives

---@type LazySpec
return {
  "nvimtools/none-ls.nvim",
  enabled = false, -- Disabled due to Neovim 0.11 incompatibility
  opts = function(_, opts)
    -- Add additional none-ls sources here if needed
    -- ESLint has been moved to eslint-lsp for better compatibility
  end,
}
