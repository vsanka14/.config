local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

-- Auto refresh buffer when file changes on disk
autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  group = augroup("auto_refresh_buffer", { clear = true }),
  pattern = "*",
  callback = function()
    if vim.fn.getcmdwintype() == "" then vim.cmd.checktime() end
  end,
  desc = "Auto refresh buffer if file changed on disk",
})

-- Reapply italic highlights on colorscheme change
autocmd("ColorScheme", {
  group = augroup("italic_highlights", { clear = true }),
  callback = function()
    vim.api.nvim_set_hl(0, "Comment", { italic = true })
    vim.api.nvim_set_hl(0, "Keyword", { italic = true })
  end,
  desc = "Reapply italic highlights",
})

-- MDX filetype registration
vim.filetype.add({
  extension = {
    mdx = "markdown.mdx",
  },
})

-- Markdown-specific settings
autocmd("FileType", {
  group = augroup("markdown_settings", { clear = true }),
  pattern = { "markdown", "markdown.mdx" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = "nc"
  end,
  desc = "Markdown-specific options",
})

-- Glimmer unicode fix for .hbs files
local glimmer_group = augroup("glimmer_unicode_fix", { clear = true })

autocmd({ "BufReadPost", "BufNewFile" }, {
  group = glimmer_group,
  pattern = "*.hbs",
  callback = function(args) require("helpers.ember").convert_unicode_to_char(args.buf) end,
  desc = "Convert unicode escapes to chars on load",
})

autocmd("BufWritePre", {
  group = glimmer_group,
  pattern = "*.hbs",
  callback = function(args) require("helpers.ember").convert_char_to_unicode(args.buf) end,
  desc = "Convert chars back to unicode escapes on save",
})

autocmd("BufWritePost", {
  group = glimmer_group,
  pattern = "*.hbs",
  callback = function(args) require("helpers.ember").convert_unicode_to_char(args.buf) end,
  desc = "Restore buffer to treesitter-friendly state after save",
})

-- Highlight on yank
autocmd("TextYankPost", {
  group = augroup("highlight_yank", { clear = true }),
  callback = function() vim.hl.on_yank({ timeout = 200 }) end,
  desc = "Highlight on yank",
})
