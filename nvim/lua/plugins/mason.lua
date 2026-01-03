-- Customize Mason
-- NOTE: Language servers are handled by community packs (lua, typescript, astro, mdx)

-- Detect rdev environment (LinkedIn remote dev containers use /home/coder)
local is_rdev = vim.fn.expand("~"):match("^/home/coder") ~= nil

-- Base tools (available everywhere)
local ensure_installed = {
  -- formatters
  "stylua",
  "prettier",
  -- utilities
  "tree-sitter-cli",
}

if is_rdev then
  -- rdev: use typescript-language-server (available in corporate npm)
  table.insert(ensure_installed, "typescript-language-server")
else
  -- local: use eslint-lsp (vtsls comes from pack.typescript)
  table.insert(ensure_installed, "eslint-lsp")
end

---@type LazySpec
return {
  -- use mason-tool-installer for automatically installing Mason packages
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    -- overrides `require("mason-tool-installer").setup(...)`
    opts = {
      -- Make sure to use the names found in `:Mason`
      ensure_installed = ensure_installed,
    },
  },
}
