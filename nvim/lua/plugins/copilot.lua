-- GitHub Copilot - disable for markdown files
return {
  "zbirenbaum/copilot.lua",
  opts = {
    filetypes = {
      markdown = false,
      mdx = false,
    },
    suggestion = {
      keymap = {
        accept = "<C-l>",
      },
    },
  },
}
