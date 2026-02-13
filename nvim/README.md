# Neovim Config

Built on [AstroNvim v5](https://astronvim.com/). Extended via lazy.nvim plugin specs and AstroCommunity packs.

## Loading Order

```
init.lua → lazy_setup.lua → AstroNvim core → community.lua → plugins/ → polish.lua
```

`community.lua` loads first, so anything in `plugins/` can override community defaults.

## Structure

```
lua/
├── lazy_setup.lua       # lazy.nvim bootstrap + AstroNvim spec
├── community.lua        # AstroCommunity pack imports (language packs, recipes)
├── polish.lua           # Runs last — filetype registration, final tweaks
├── helpers/             # Reusable Lua modules (require("helpers.xxx"))
└── plugins/             # One file per plugin (see conventions below)
```

## Conventions

**Plugin files** — One file per plugin in `plugins/`, named after the plugin (`gitsigns.lua`, `conform.lua`). Each returns a lazy.nvim spec:

```lua
return { "author/plugin.nvim", opts = { ... } }
```

Use `opts` for declarative config. Use `config = function()` only when `opts` isn't enough. Disable a plugin with `enabled = false`.

**Keymaps** — Centralized in `plugins/astrocore.lua` under `mappings`. Organized by mode (`n`, `v`, `t`). Leader is `<Space>`, LocalLeader is `,`. Group prefixes: `<Leader>g` for git, `<Leader>a` for AI, `<Leader>m` for markdown, `<Leader>u` for toggles. Filetype-specific keymaps go in autocmds scoped to the buffer.

**LSP** — Configured in `plugins/astrolsp.lua`. Language servers come from AstroCommunity packs or Mason. LSP formatting is disabled in favor of conform.nvim.

**Formatting** — `plugins/conform.lua` handles format-on-save. Add formatters per filetype in `formatters_by_ft`. Mason auto-installs tools listed in `plugins/mason.lua`.

**Filetype-specific behavior** — Custom filetypes registered in `polish.lua`. Per-filetype completion, formatting, and options set in their respective plugin files.

**Helpers** — Shared Lua functions live in `lua/helpers/` and are loaded with `require("helpers.module")`.
