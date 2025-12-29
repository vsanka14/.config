-- This will run last in the setup process.
-- This is just pure lua so anything that doesn't
-- fit in the normal config locations above can go here

-- Auto-refresh Neo-tree git status when Neovim regains focus
-- This fixes stale git status after external git operations (push, commit, etc.)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  pattern = "*",
  callback = function()
    if package.loaded["neo-tree.sources.manager"] then
      require("neo-tree.sources.manager").refresh("filesystem")
    end
  end,
})
