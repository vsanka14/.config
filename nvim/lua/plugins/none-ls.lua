-- Customize None-ls sources (linters)

---@type LazySpec
return {
  "nvimtools/none-ls.nvim",
  opts = function(_, opts)
    local null_ls = require "null-ls"

    -- Only insert new sources, do not replace the existing ones
    opts.sources = require("astrocore").list_insert_unique(opts.sources, {
      -- Linters
      null_ls.builtins.diagnostics.eslint_d, -- JS/TS linting (fast daemon version)
    })
  end,
}
