-- Add custom icon support to mini.icons
return {
  "echasnovski/mini.icons",
  opts = {
    extension = {
      astro = { glyph = "󱓞", hl = "MiniIconsOrange" },
      mdx = { glyph = "󰍔", hl = "MiniIconsAzure" },
      hbs = { glyph = "\u{e60f}", hl = "MiniIconsOrange" },
    },
  },
}
