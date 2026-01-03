# rdev Dotfiles Setup Progress

## Summary

Setup dotfiles for LinkedIn rdev (remote development) environment.

## Completed

### Git Configuration
- Removed old remote (`vsanka14/vsankar-dotfiles`)
- Added new remote (`vsankar_LinkedIn/dotfiles`)
- Set local git identity for repo:
  - `user.name`: Vasisht Shankar
  - `user.email`: vsankar@linkedin.com
- Updated `.gitconfig` with work email

### Neovim Installation
- Fixed download URL (changed from `nvim.appimage` to `nvim-linux-x86_64.appimage`)
- Added download validation and error handling
- Successfully installed **Neovim v0.11.5** to `~/.local/bin/nvim`
- Note: System has old nvim v0.6.1 at `/usr/local/bin/nvim` - PATH priority matters

### Shell Configuration
- Install script adds `exec zsh` to `~/.bash_profile` for auto-switch to zsh
- zshrc adds `~/.local/bin` to PATH (required for user-installed tools)

### Conditional Neovim Config (rdev vs local)

The nvim config detects rdev by checking if `$HOME` starts with `/home/coder`:

```lua
local is_rdev = vim.fn.expand("~"):match("^/home/coder") ~= nil
```

#### On rdev:
| Feature | Status | Notes |
|---------|--------|-------|
| `typescript-language-server` | ✅ | TS/JS autocomplete, auto-imports, types |
| `eslint-lsp` | ❌ | Not available in corporate npm |
| `prettier` | ✅ | Formatting works |
| `pack.typescript` (vtsls) | ❌ | Skipped, uses typescript-language-server instead |
| `pack.astro` | ❌ | Skipped |
| `pack.mdx` | ❌ | Skipped |

#### On local Mac:
| Feature | Status | Notes |
|---------|--------|-------|
| `vtsls` | ✅ | Via pack.typescript |
| `eslint-lsp` | ✅ | Full eslint support |
| `prettier` | ✅ | Formatting works |
| `pack.astro` | ✅ | Full astro support |
| `pack.mdx` | ✅ | Full mdx support |

### Mason Packages Status (rdev)

| Package | Status |
|---------|--------|
| lua-language-server | ✅ Installed |
| stylua | ✅ Installed |
| selene | ✅ Installed |
| marksman | ✅ Installed |
| prettier | ✅ Installed |
| tree-sitter-cli | ✅ Installed |
| js-debug-adapter | ✅ Installed |
| typescript-language-server | ✅ Installed (rdev only) |

## Known Limitations

### Corporate npm Registry

LinkedIn rdev uses Artifactory (`dev-artifactory.corp.linkedin.com`) as npm proxy. Some packages aren't mirrored:

- `@vtsls/language-server`
- `vscode-langservers-extracted` (eslint-lsp)
- `@mdx-js/language-server`
- `@astrojs/language-server`

### No eslint in nvim on rdev

Workarounds:
1. Request packages be added to Artifactory
2. Rely on CI/pre-commit hooks for eslint errors

### DNF Package Differences

rdev uses Azure Linux/Mariner. Some packages have different names:
- `fd-find` -> `fd` (or unavailable)
- `util-linux-user` -> unavailable

Install script handles this gracefully.

## Files with Conditional Logic

- `nvim/lua/community.lua` - Conditional pack loading
- `nvim/lua/plugins/mason.lua` - Conditional LSP/tool installation

## Quick Setup on New rdev

```bash
git clone git@github.com:vsankar_LinkedIn/dotfiles.git ~/.config
cd ~/.config
./install.sh
# Start new terminal session (zsh auto-starts)
# Open nvim - plugins install automatically
```
