-- AstroCommunity: import any community modules here
-- We import this file in `lazy_setup.lua` before the `plugins/` folder.
-- This guarantees that the specs are processed before any user plugins.

---@type LazySpec
return {
  "AstroNvim/astrocommunity",
  -- Language packs (includes LSP, treesitter, and tooling)
  { import = "astrocommunity.pack.lua" },
  { import = "astrocommunity.pack.typescript" },
  { import = "astrocommunity.pack.astro" },
  { import = "astrocommunity.pack.mdx" },
  -- UI customizations
  { import = "astrocommunity.recipes.heirline-mode-text-statusline" },
  -- Git plugins configured in plugins/user.lua with custom options
}
