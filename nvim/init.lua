-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Set leader before lazy
vim.g.mapleader = " "
vim.g.maplocalleader = ","

-- Core modules
require("options")
require("autocmds")

-- Setup lazy.nvim (loads lua/plugins/*.lua)
require("lazy").setup({
  spec = { import = "plugins" },
  install = { colorscheme = { "tokyonight" } },
  checker = { enabled = false },
  change_detection = { notify = false },
})

-- Modules that depend on plugins being available
require("keymaps")
require("statusline")
require("tabline")
require("lsp")
require("helpers.trino").setup()

-- Show startup time as a notification
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.schedule(function()
      local stats = require("lazy").stats()
      local ms = math.floor(stats.startuptime * 100 + 0.5) / 100
      vim.notify(string.format("Loaded %d plugins in %.2fms", stats.loaded, ms))
    end)
  end,
})
