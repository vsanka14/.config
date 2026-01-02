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
      lua = { "stylua" },
      gitignore = { "trim_whitespace" },
    },
    formatters = {
      prettier = {
        prepend_args = function(self, ctx)
          -- Use glimmer parser for .hbs files
          if vim.fn.expand("%:e") == "hbs" then
            return { "--parser", "glimmer" }
          end
          return {}
        end,
      },
    },
    format_on_save = {
      timeout_ms = 1000,
      lsp_fallback = false,
    },
  },
}
