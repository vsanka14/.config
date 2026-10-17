# Neovim Config

Personal Neovim configuration.

## Requirements

- Neovim 0.12+
- `tree-sitter-cli` 0.26.1+ (`brew install tree-sitter-cli`, not npm) and a C compiler, to build parsers

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
- **treesitter** -- Syntax highlighting / indent / folds / textobjects (`main` branch)
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

## Treesitter

`nvim-treesitter` and `nvim-treesitter-textobjects` use the `main` branch. That branch has no modules, so
`lua/plugins/treesitter.lua` does this setup:

- Installs the parsers in its `parsers` list to `stdpath("data")/site/parser` (no-op when already installed).
- A `FileType` autocmd starts highlighting and sets the treesitter `indentexpr` when the language has the query for it.
  It also sets buffer-local textobject maps (`af`/`if`/`ac`/`ic`/`aa`/`ia`, `]f`/`[f`/`]c`/`[c`).
- Folds use the built-in `vim.treesitter.foldexpr()` (`options.lua`).

After you update the plugin, run `:TSUpdate`.

## CodeDiff navigation

In the CodeDiff explorer, file jumps from the working-tree pane also update the
comparison. Definition and reference jumps, and native `Ctrl+o` / `Ctrl+i`, use
the same listener. The helper uses the explorer's comparison rules, including
rename paths and the index base for files with staged and unstaged changes.
It does not move the cursor to the first change.

Files outside the explorer's working-tree changes open in a separate source
tab. The previous comparison and cursor remain in the diff tab. Native jump
history is copied to the source tab; jumps there remain normal source navigation.
Revision panes, staged-only comparisons, history views, and conflicts are not
handled. Bare `:CodeDiff file HEAD` views use CodeDiff's native file listener.

The helper uses CodeDiff's internal selection API. Check navigation after
updating CodeDiff.
