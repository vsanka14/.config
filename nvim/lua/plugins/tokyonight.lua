-- Tokyo Night theme configuration with transparency support
return {
  "folke/tokyonight.nvim",
  lazy = false,
  priority = 1000,
  opts = {
    style = "night", -- storm, moon, night, day
    transparent = true, -- Enable transparent background
    terminal_colors = true,
    styles = {
      -- Style to be applied to different syntax groups
      comments = { italic = true },
      keywords = { italic = true },
      functions = {},
      variables = {},
      -- Background styles: NONE, transparent, dark, normal
      sidebars = "transparent", -- NeoTree, terminal, etc.
      floats = "dark", -- Keep popups/floating windows readable
    },
    sidebars = { "qf", "help", "terminal", "packer" },
    day_brightness = 0.3,
    hide_inactive_statusline = false,
    dim_inactive = false,
    lualine_bold = false,

    on_colors = function(colors)
      -- You can customize specific colors here if needed
    end,
    on_highlights = function(highlights, colors)
      -- Additional highlight customizations
      highlights.NeoTreeDirectoryName = { fg = "#c9c7cd" }
    end,
  },
}
