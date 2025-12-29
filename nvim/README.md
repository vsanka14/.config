# Neovim Config Breakdown

## Architecture Overview

Your config is built on **AstroNvim v5** - a pre-configured Neovim distribution. The loading order is:

```
init.lua -> lazy_setup.lua -> [AstroNvim core, community/, plugins/]
```

---

## Plugin Categories

### Core Framework (Required)

| Plugin | Purpose |
|--------|---------|
| **AstroNvim** | Base distribution - provides sensible defaults, UI, keymaps |
| **astrocore** | Core settings, options, mappings |
| **astrolsp** | LSP configuration engine |
| **astroui** | UI theming and icons |

### Package Management

| Plugin | Purpose |
|--------|---------|
| **lazy.nvim** | Plugin manager (bootstrapped in init.lua) |
| **mason-tool-installer** | Auto-installs LSPs, formatters, linters |

### Code Intelligence

| Plugin | Purpose |
|--------|---------|
| **nvim-treesitter** | Syntax highlighting, code parsing |
| **blink.cmp** | Autocompletion engine |
| **lsp_signature.nvim** | Function signature hints |
| **LuaSnip** | Snippet engine |

### Formatting & Linting

| Plugin | Purpose |
|--------|---------|
| **conform.nvim** | Code formatting on save (prettier, stylua) |
| **none-ls.nvim** | Linters (eslint_d, shellcheck, markdownlint) |

### Git Integration (GitLens-like)

| Plugin | Purpose |
|--------|---------|
| **gitsigns.nvim** | Inline git signs, always-on EOL blame, hunk staging |
| **git-blame.nvim** | Toggle-able full blame display |
| **diffview.nvim** | Advanced diff/history viewer |
| **neogit** | Full git UI (like magit) |

### UI & Navigation

| Plugin | Purpose |
|--------|---------|
| **snacks.nvim** | Dashboard with random ASCII headers |
| **neo-tree.nvim** | File explorer (shows hidden files) |
| **mini.icons** | Icons (includes Astro icon) |
| **nvim-autopairs** | Auto-close brackets/quotes |

### Markdown

| Plugin | Purpose |
|--------|---------|
| **glow.nvim** | Terminal preview using `glow` CLI |
| **markdown-preview.nvim** | Live browser preview with hot reload |

---

## Installed Tools (via Mason)

### Language Servers
- `lua-language-server` - Lua
- `typescript-language-server` - JS/TS
- `astro-language-server` - Astro
- `mdx-analyzer` - MDX

### Formatters
- `stylua` - Lua
- `prettier` - JS/TS/CSS/HTML/JSON/YAML/Markdown

### Linters
- `eslint_d` - JS/TS (fast daemon version)
- `shellcheck` - Shell scripts
- `markdownlint` - Markdown

### Other
- `debugpy` - Python debugger
- `tree-sitter-cli` - Treesitter grammar compiler

---

## Linting Behavior

Linters run automatically and show diagnostics:
- **On file open** - immediate feedback
- **On save** - re-checks the file
- **As you type** - eslint_d supports this

Diagnostics appear as:
- Squiggly underlines in the editor
- Signs in the gutter (left margin)
- Listed in `:Telescope diagnostics`

**Note**: Linters do NOT block git commits. For commit blocking, set up pre-commit hooks in your project (husky, lint-staged, etc.).

---

## Keybinding Summary

| Key | Action |
|-----|--------|
| `<Space>` | Leader key |
| `jk` | Exit insert mode |

### Git (`<Leader>g`)
| Key | Action |
|-----|--------|
| `<Leader>gb` | Toggle git blame |
| `<Leader>gB` | Full blame for current line |
| `<Leader>gd` | Open diff view |
| `<Leader>gh` | File history |
| `<Leader>gH` | Project history |
| `<Leader>gg` | Open Neogit |
| `<Leader>gp` | Preview hunk |
| `<Leader>gr` | Reset hunk |
| `<Leader>gs` | Stage hunk |
| `]h` / `[h` | Next/Prev git hunk |

### Markdown (`<Leader>m`)
| Key | Action |
|-----|--------|
| `<Leader>mp` | Preview in terminal (Glow) |
| `<Leader>mb` | Preview in browser |
| `<Leader>ms` | Stop browser preview |

### Buffers
| Key | Action |
|-----|--------|
| `]b` / `[b` | Next/Prev buffer |
| `<Leader>bd` | Close buffer from tabline |

---

## Markdown Editing Experience

### Editing Features
- **Word wrap** enabled globally (`wrap = true`, `linebreak = true`)
- **Conceal** enabled for markdown (hides syntax like `**bold**` showing **bold**)
- **Autocompletion disabled** for markdown/text files (less noise when writing prose)
- **Prettier** formats on save

### Preview Options
| Command | What it does |
|---------|--------------|
| `<Leader>mp` | Opens Glow in a floating terminal window - fast, stays in nvim |
| `<Leader>mb` | Opens browser with live preview - auto-refreshes as you type |
| `<Leader>ms` | Stops the browser preview server |

### MDX Support
- Filetype detection for `.mdx` files
- Uses markdown treesitter parser
- LSP via `mdx-analyzer`

### Dependencies
- `glow` CLI (installed via brew) - required for terminal preview
- Browser preview installs its own npm dependencies on first use

---

## File Structure

```
nvim/
├── init.lua                 # Bootstrap lazy.nvim
├── lua/
│   ├── lazy_setup.lua       # Lazy.nvim config, loads AstroNvim
│   ├── community.lua        # AstroCommunity imports (lua pack)
│   ├── polish.lua           # Post-setup customizations (empty)
│   └── plugins/
│       ├── astrocore.lua    # Core settings, keymaps, options
│       ├── astrolsp.lua     # LSP configuration
│       ├── astroui.lua      # Theme, icons
│       ├── blink-cmp.lua    # Completion settings
│       ├── conform.lua      # Formatters
│       ├── mason.lua        # Tool installation
│       ├── mdx.lua          # MDX support
│       ├── none-ls.lua      # Linters
│       ├── treesitter.lua   # Syntax highlighting
│       └── user.lua         # Custom plugins (git, markdown, etc.)
```

---

## Remaining Considerations

### Optional Improvements
- **DAP config** - debugpy is installed but no debug UI configured
- **Pre-commit hooks** - if you want linting to block commits (per-project setup)

### Intentional Redundancies (kept by choice)
- **git-blame.nvim + gitsigns** - two different blame modes (toggle vs always-on)
