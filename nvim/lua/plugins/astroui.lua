-- AstroUI provides the basis for configuring the AstroNvim User Interface
-- Configuration documentation can be found with `:h astroui`
-- NOTE: We highly recommend setting up the Lua Language Server (`:LspInstall lua_ls`)
--       as this provides autocomplete and documentation while editing

---@type LazySpec
return {
  "AstroNvim/astroui",
  ---@type AstroUIOpts
  opts = {
    -- change colorscheme
    colorscheme = "tokyonight-night",
    -- AstroUI allows you to easily modify highlight groups easily for any and all colorschemes
    highlights = {
      init = { -- this table overrides highlights in all themes
        -- Transparency is now handled by Tokyo Night theme config
        NeoTreeDirectoryName = { fg = "#c9c7cd" }, -- Off-white folder names (icon stays blue)
        -- Git conflict highlighting (for git-conflict.nvim)
        GitConflictCurrent = { bg = "#2e4b3e" }, -- green tint for ours/HEAD
        GitConflictCurrentLabel = { bg = "#3d6b52", bold = true },
        GitConflictIncoming = { bg = "#3d4b5c" }, -- blue tint for theirs
        GitConflictIncomingLabel = { bg = "#4d6080", bold = true },
        GitConflictAncestor = { bg = "#4a3d4e" }, -- purple tint for base
        GitConflictAncestorLabel = { bg = "#5c4d62", bold = true },
        SnacksDashboardHeader = { fg = "#bb9af7" }, -- Tokyo Night magenta
      },
      astrodark = { -- a table of overrides/changes when applying the astrotheme theme
        -- Normal = { bg = "#000000" },
      },
    },
    -- Icons can be configured throughout the interface
    icons = {
      -- configure the loading of the lsp in the status line
      LSPLoading1 = "⠋",
      LSPLoading2 = "⠙",
      LSPLoading3 = "⠹",
      LSPLoading4 = "⠸",
      LSPLoading5 = "⠼",
      LSPLoading6 = "⠴",
      LSPLoading7 = "⠦",
      LSPLoading8 = "⠧",
      LSPLoading9 = "⠇",
      LSPLoading10 = "⠏",
    },
  },
}
