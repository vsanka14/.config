# Neovim Config

Personal Neovim configuration.

## Structure

```
init.lua          -- Entry point: bootstraps lazy.nvim, loads core modules
lua/
  options.lua     -- Editor options
  keymaps.lua     -- Key mappings
  autocmds.lua    -- Autocommands
  statusline.lua  -- Custom statusline
  tabline.lua     -- Custom tabline
  lsp.lua         -- LSP configuration (off by default; :LspToggle)
  helpers/        -- Utility modules (git blame, floating terminal, icons, etc.)
  plugins/        -- Plugin specs loaded by lazy.nvim
```

## Plugins

Managed with [lazy.nvim](https://github.com/folke/lazy.nvim). Key plugins:

- **blink-cmp** -- Completion
- **conform** -- Formatting (LSP-independent)
- **gutentags** -- Background ctags indexer for no-LSP navigation
- **mason** -- LSP/tool installer
- **nvim-jdtls** -- Java LSP
- **nvim-dap** -- Java Debugging
- **treesitter** -- Syntax highlighting / folds / textobjects
- **mini** -- Collection of small utilities (pick, diff, surround, ...)
- **diffview** -- Git diff viewer
- **tokyonight** -- Colorscheme
