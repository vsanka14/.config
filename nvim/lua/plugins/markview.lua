-- Markview: Markdown, HTML, LaTeX, Typst & YAML previewer
-- https://github.com/OXY2DEV/markview.nvim

---@type LazySpec
return {
  "OXY2DEV/markview.nvim",
  -- Remove lazy = false to let plugin self-manage lazy-loading
  ft = { "markdown", "mdx" }, -- Explicitly load on markdown filetypes
}
