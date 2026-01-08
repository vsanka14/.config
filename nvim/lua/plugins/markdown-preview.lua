-- Browser-based markdown preview (live reload)
return {
  "iamcco/markdown-preview.nvim",
  cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
  ft = { "markdown", "mdx" },
  build = "cd app && npm install",
  init = function()
    vim.g.mkdp_filetypes = { "markdown", "mdx" }
    vim.g.mkdp_auto_close = 0 -- Don't auto-close when switching buffers
    vim.g.mkdp_theme = "dark"
  end,
}
