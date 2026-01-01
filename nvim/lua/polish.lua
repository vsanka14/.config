-- This will run last in the setup process.
-- This is just pure lua so anything that doesn't
-- fit in the normal config locations above can go here

-- ============================================================================
-- MDX Filetype Support
-- ============================================================================
-- Register MDX filetype and use markdown parser for syntax highlighting

vim.filetype.add({
  extension = {
    mdx = "mdx",
  },
})

-- Use markdown treesitter parser for MDX files
vim.treesitter.language.register("markdown", "mdx")
