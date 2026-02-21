-- Add Mason bin to PATH so conform/DAP can find installed tools
vim.env.PATH = vim.fn.stdpath("data") .. "/mason/bin:" .. vim.env.PATH

local opt = vim.opt

opt.relativenumber = true
opt.number = true
opt.spell = false
opt.signcolumn = "yes"
opt.wrap = true
opt.linebreak = true
opt.textwidth = 0
opt.wrapmargin = 0
opt.autoread = true
opt.termguicolors = true
opt.showmode = false -- statusline handles this
opt.splitbelow = true
opt.splitright = true
opt.mouse = "a"
opt.ignorecase = true
opt.smartcase = true
opt.undofile = true
opt.updatetime = 250
opt.completeopt = "menuone,noselect,popup"
opt.clipboard = "unnamedplus"
opt.cursorline = true
opt.scrolloff = 8
opt.cmdheight = 0
opt.hlsearch = true
opt.incsearch = true
opt.list = true
opt.listchars = { leadmultispace = "│ ", tab = "│ ", trail = "·" }
opt.shiftwidth = 2
opt.tabstop = 2
