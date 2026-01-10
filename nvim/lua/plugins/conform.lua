---@type LazySpec
return {
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = { "ConformInfo" },
  opts = {
    formatters_by_ft = {
      astro = { "prettier" },
      javascript = { "prettier" },
      typescript = { "prettier" },
      javascriptreact = { "prettier" },
      typescriptreact = { "prettier" },
      css = { "prettier" },
      html = { "prettier" },
      json = { "prettier" },
      yaml = { "prettier" },
      markdown = { "prettier" },
      mdx = { "prettier" },
      handlebars = { "prettier" },
      sql = { "sql_formatter" },
      lua = { "stylua" },
      gitignore = { "trim_whitespace" },
    },
    formatters = {
      prettier = {
        -- Use project-local prettier if available, otherwise fall back to Mason's prettier
        command = require("conform.util").from_node_modules "prettier",
        prepend_args = function(self, ctx)
          -- Use glimmer parser for .hbs files
          if vim.fn.expand "%:e" == "hbs" then return { "--parser", "glimmer" } end
          return {}
        end,
      },
      sql_formatter = {
        prepend_args = { "-c", '{"keywordCase":"lower"}' },
      },
    },
    format_on_save = {
      timeout_ms = 1000,
      lsp_fallback = false,
    },
  },
}
