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
  helpers/        -- Utility modules (git blame, floating terminal, etc.)
  plugins/        -- Plugin specs loaded by lazy.nvim
```

## Plugins

Managed with [lazy.nvim](https://github.com/folke/lazy.nvim). Key plugins:

- **blink-cmp** -- Completion (buffer + ctags sources)
- **conform** -- Formatting
- **gutentags** -- Background ctags indexer for no-LSP navigation
- **treesitter** -- Syntax highlighting / indent / folds / textobjects (`main` branch)
- **mini** -- Collection of small utilities (pick, diff, surround, ...)
- **diffview** -- Git diff viewer
- **tokyonight** -- Colorscheme
