-- Disable blink.cmp completion for markdown and text files

---@type LazySpec
return {
  "saghen/blink.cmp",
  opts = {
    sources = {
      default = { "lsp", "path", "snippets", "buffer" },
      per_filetype = {
        markdown = {}, -- No completion sources for markdown
        text = {}, -- No completion sources for text files
      },
    },
  },
}