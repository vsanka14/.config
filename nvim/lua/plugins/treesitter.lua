-- Customize Treesitter

---@type LazySpec
return {
  "nvim-treesitter/nvim-treesitter",
  dependencies = {
    "andymass/vim-matchup", -- Enhanced bracket matching
  },
  opts = {
    ensure_installed = {
      "lua",
      "vim",
      "markdown",
      "markdown_inline",
      "tsx",
      "javascript",
      "typescript",
      "glimmer",
    },
    matchup = {
      enable = true, -- Enable treesitter integration for vim-matchup
    },
  },
}
