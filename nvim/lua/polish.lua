-- This will run last in the setup process.
-- This is just pure lua so anything that doesn't
-- fit in the normal config locations above can go here

-- ============================================================================
-- MDX Filetype Support
-- ============================================================================
-- Register MDX filetype and use markdown parser for syntax highlighting

vim.filetype.add {
  extension = {
    mdx = "mdx",
  },
}

-- Use markdown treesitter parser for MDX files
vim.treesitter.language.register("markdown", "mdx")

-- ============================================================================
-- Italic Highlights (merges with existing colorscheme colors)
-- ============================================================================
-- Helper function to add italic to existing highlight groups
local function italicize(group)
  local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
  hl.italic = true
  vim.api.nvim_set_hl(0, group, hl)
end

-- Apply italics after colorscheme loads
vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "*",
  callback = function()
    -- Comments
    italicize "Comment"

    -- Keywords
    italicize "@keyword"
    italicize "@keyword.return"
    italicize "@keyword.function"
    italicize "@keyword.operator"
    italicize "@keyword.conditional"
    italicize "@keyword.repeat"
    italicize "@keyword.import"

    -- this/self
    italicize "@variable.builtin"
  end,
})

-- Also apply immediately for the current session
vim.defer_fn(function()
  italicize "Comment"
  italicize "@keyword"
  italicize "@keyword.return"
  italicize "@keyword.function"
  italicize "@keyword.operator"
  italicize "@keyword.conditional"
  italicize "@keyword.repeat"
  italicize "@keyword.import"
  italicize "@variable.builtin"
end, 0)
