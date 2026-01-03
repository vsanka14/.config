-- AstroCommunity: import any community modules here
-- We import this file in `lazy_setup.lua` before the `plugins/` folder.
-- This guarantees that the specs are processed before any user plugins.

-- Detect rdev environment (LinkedIn remote dev containers use /home/coder)
local is_rdev = vim.fn.expand("~"):match("^/home/coder") ~= nil

---@type LazySpec
local spec = {
  "AstroNvim/astrocommunity",
  -- AI completion
  { import = "astrocommunity.completion.copilot-lua" },
  -- Language packs (includes LSP, treesitter, and tooling)
  { import = "astrocommunity.pack.lua" },
  -- UI customizations
  { import = "astrocommunity.recipes.heirline-mode-text-statusline" },
  -- Git plugins configured in plugins/user.lua with custom options
}

-- Local-only packs (not available on rdev due to corporate npm registry)
if not is_rdev then
  table.insert(spec, { import = "astrocommunity.pack.typescript" })
  table.insert(spec, { import = "astrocommunity.pack.astro" })
  table.insert(spec, { import = "astrocommunity.pack.mdx" })
end

return spec
