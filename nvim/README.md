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

- **blink-cmp** -- Completion (buffer + ctags sources; no LSP)
- **conform** -- Formatting (LSP-independent)
- **gutentags** -- Background ctags indexer for no-LSP navigation
- **treesitter** -- Syntax highlighting / folds / textobjects
- **mini** -- Collection of small utilities (pick, diff, surround, ...)
- **diffview** -- Git diff viewer
- **tokyonight** -- Colorscheme

## No-LSP navigation

This branch runs **without any LSP**. Code navigation and completion come from a
lightweight ctags + ripgrep stack instead:

- `gd` / `<C-]>` -- go to definition via ctags (`helpers.tags`)
- `gr` -- find references via ripgrep (mini.pick)
- blink-cmp **tags** source -- cross-file symbol completion from the ctags index
- **gutentags** -- keeps the ctags index fresh (on-focus, debounced)
- `<Leader>ft` -- regenerate the tags index on demand

The full LSP setup (servers, `:LspToggle`, jdtls, mason, dap) is preserved on the
`with-lsp` branch if semantic features are ever needed again.
