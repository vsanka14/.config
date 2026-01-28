---@type LazySpec
return {
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = { "ConformInfo" },
  opts = {
    log_level = vim.log.levels.DEBUG,
    formatters_by_ft = {
      astro = { "prettier" },
      javascript = { "prettier" },
      typescript = { "prettier" },
      javascriptreact = { "prettier" },
      typescriptreact = { "prettier" },
      css = { "prettier" },
      scss = { "prettier" },
      html = { "prettier" },
      json = { "prettier" },
      yaml = { "prettier" },
      markdown = { "prettier" },
      mdx = { "prettier" },
      handlebars = { "prettier" },
      sql = { "sql_formatter" },
      lua = { "stylua" },
      java = { "google-java-format" },
      gitignore = { "trim_whitespace" },
    },
    formatters = {
      prettier = {
        -- Use project's node_modules prettier if available, otherwise fall back to Mason
        command = require("conform.util").from_node_modules("prettier"),
        prepend_args = function(self, ctx)
          local args = {}
          -- Find and use project's .prettierrc
          local config_path = vim.fn.findfile(".prettierrc", vim.fn.expand("%:p:h") .. ";")
          if config_path ~= "" then
            table.insert(args, "--config")
            table.insert(args, config_path)
          end
          -- Use glimmer parser for .hbs files
          if vim.fn.expand "%:e" == "hbs" then
            table.insert(args, "--parser")
            table.insert(args, "glimmer")
          end
          return args
        end,
      },
      sql_formatter = {
        prepend_args = { "-c", '{"keywordCase":"lower"}' },
      },
      ["google-java-format"] = {
        prepend_args = {},
      },
    },
    format_on_save = {
      timeout_ms = 1000,
      lsp_fallback = false,
    },
  },
}
