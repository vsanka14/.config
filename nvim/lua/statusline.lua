local M = {}

local mode_map = {
  ["n"]     = "NORMAL",
  ["no"]    = "OP-PENDING",
  ["nov"]   = "OP-PENDING",
  ["noV"]   = "OP-PENDING",
  ["no\22"] = "OP-PENDING",
  ["niI"]   = "NORMAL",
  ["niR"]   = "NORMAL",
  ["niV"]   = "NORMAL",
  ["nt"]    = "NORMAL",
  ["v"]     = "VISUAL",
  ["vs"]    = "VISUAL",
  ["V"]     = "VISUAL LINE",
  ["Vs"]    = "VISUAL LINE",
  ["\22"]   = "VISUAL BLOCK",
  ["\22s"]  = "VISUAL BLOCK",
  ["s"]     = "SELECT",
  ["S"]     = "SELECT LINE",
  ["\19"]   = "SELECT BLOCK",
  ["i"]     = "INSERT",
  ["ic"]    = "INSERT",
  ["ix"]    = "INSERT",
  ["R"]     = "REPLACE",
  ["Rc"]    = "REPLACE",
  ["Rx"]    = "REPLACE",
  ["Rv"]    = "VISUAL REPLACE",
  ["Rvc"]   = "VISUAL REPLACE",
  ["Rvx"]   = "VISUAL REPLACE",
  ["c"]     = "COMMAND",
  ["cv"]    = "EX",
  ["ce"]    = "EX",
  ["r"]     = "ENTER",
  ["rm"]    = "MORE",
  ["r?"]    = "CONFIRM",
  ["!"]     = "SHELL",
  ["t"]     = "TERMINAL",
}

local mode_hl = {
  NORMAL = "StatusLineMode",
  INSERT = "StatusLineModeInsert",
  VISUAL = "StatusLineModeVisual",
  ["VISUAL LINE"] = "StatusLineModeVisual",
  ["VISUAL BLOCK"] = "StatusLineModeVisual",
  REPLACE = "StatusLineModeReplace",
  ["VISUAL REPLACE"] = "StatusLineModeReplace",
  COMMAND = "StatusLineModeCommand",
  TERMINAL = "StatusLineModeTerm",
  SELECT = "StatusLineModeVisual",
  ["SELECT LINE"] = "StatusLineModeVisual",
  ["SELECT BLOCK"] = "StatusLineModeVisual",
}

-- ============================================================================
-- Cached state (updated via autocmds, never computed in render)
-- ============================================================================
local cache = {
  git_branch = "",
  lsp_progress = "",
  lsp_clients = "",
  diag = "",
}

-- Git branch (async job, updated on BufEnter/FocusGained)
local function update_git_branch()
  local buf_dir = vim.fn.expand("%:p:h")
  if buf_dir == "" then
    cache.git_branch = ""
    return
  end
  vim.fn.jobstart({ "git", "-C", buf_dir, "rev-parse", "--abbrev-ref", "HEAD" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      cache.git_branch = (data and data[1] and data[1] ~= "") and data[1] or ""
    end,
    on_exit = function(_, code)
      if code ~= 0 then cache.git_branch = "" end
    end,
  })
end

-- Diagnostics (cached string, updated on DiagnosticChanged)
local function update_diagnostics()
  local icons = {
    { vim.diagnostic.severity.ERROR, "StatusLineDiagError", "\u{f0674} " },
    { vim.diagnostic.severity.WARN,  "StatusLineDiagWarn",  "\u{f0026} " },
    { vim.diagnostic.severity.INFO,  "StatusLineDiagInfo",  "\u{f02fc} " },
    { vim.diagnostic.severity.HINT,  "StatusLineDiagHint",  "\u{f0835} " },
  }
  local parts = {}
  for _, d in ipairs(icons) do
    local count = #vim.diagnostic.get(0, { severity = d[1] })
    if count > 0 then
      parts[#parts + 1] = "%#" .. d[2] .. "#" .. d[3] .. count .. " %*"
    end
  end
  cache.diag = table.concat(parts)
end

-- LSP clients (cached string, updated on LspAttach/LspDetach)
local function update_lsp_clients()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients > 0 then
    local names = {}
    for _, c in ipairs(clients) do
      names[#names + 1] = c.name
    end
    cache.lsp_clients = table.concat(names, ", ")
  else
    cache.lsp_clients = ""
  end
end

-- LSP progress (updated on LspProgress events)
local lsp_progress_map = {}

local function update_lsp_progress(args)
  local data = args.data
  if not data or not data.params then return end
  local val = data.params.value
  local client_id = data.client_id
  if not val or not client_id then return end

  if val.kind == "end" then
    lsp_progress_map[client_id] = nil
  else
    local msg = val.title or ""
    if val.message then msg = msg .. ": " .. val.message end
    if val.percentage then msg = msg .. " (" .. val.percentage .. "%%%%)" end
    lsp_progress_map[client_id] = msg
  end

  local msgs = {}
  for _, msg in pairs(lsp_progress_map) do
    msgs[#msgs + 1] = msg
  end
  cache.lsp_progress = table.concat(msgs, " | ")
end

-- ============================================================================
-- Autocmds to keep cache fresh
-- ============================================================================
local group = vim.api.nvim_create_augroup("statusline_cache", { clear = true })

vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "DirChanged" }, {
  group = group, callback = update_git_branch,
})

vim.api.nvim_create_autocmd("DiagnosticChanged", {
  group = group, callback = update_diagnostics,
})

vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach", "BufEnter" }, {
  group = group, callback = update_lsp_clients,
})

vim.api.nvim_create_autocmd("LspProgress", {
  group = group, callback = update_lsp_progress,
})

-- Initial fetch
update_git_branch()

-- ============================================================================
-- Render (pure string concat, no API calls)
-- ============================================================================
function M.render()
  local mode = vim.api.nvim_get_mode().mode
  local mode_label = mode_map[mode] or mode
  local hl = mode_hl[mode_label] or "StatusLineMode"

  -- Left: mode + file + git
  local left = "%#" .. hl .. "# " .. mode_label .. " %*"
    .. "%#StatusLineFile# %t %m%r%*"
  if cache.git_branch ~= "" then
    left = left .. "%#StatusLineGit#  " .. cache.git_branch .. " %*"
  end

  -- Right: diagnostics + lsp + position
  local right = cache.diag
  if cache.lsp_progress ~= "" then
    right = right .. "%#StatusLineLsp# " .. cache.lsp_progress .. " %*"
  elseif cache.lsp_clients ~= "" then
    right = right .. "%#StatusLineLsp# " .. cache.lsp_clients .. " %*"
  end
  right = right .. "%#StatusLinePos# %l:%c %p%% %*"

  return left .. "%=" .. right
end

-- ============================================================================
-- Highlights
-- ============================================================================
local function setup_highlights()
  local colors = {
    StatusLineMode        = { fg = "#1a1b26", bg = "#7aa2f7", bold = true },
    StatusLineModeInsert   = { fg = "#1a1b26", bg = "#9ece6a", bold = true },
    StatusLineModeVisual   = { fg = "#1a1b26", bg = "#bb9af7", bold = true },
    StatusLineModeReplace  = { fg = "#1a1b26", bg = "#f7768e", bold = true },
    StatusLineModeCommand  = { fg = "#1a1b26", bg = "#e0af68", bold = true },
    StatusLineModeTerm     = { fg = "#1a1b26", bg = "#7dcfff", bold = true },
    StatusLineFile         = { fg = "#c0caf5", bg = "#24283b", bold = true },
    StatusLineGit          = { fg = "#7aa2f7", bg = "#1a1b26" },
    StatusLineDiagError    = { fg = "#f7768e", bg = "#1a1b26" },
    StatusLineDiagWarn     = { fg = "#e0af68", bg = "#1a1b26" },
    StatusLineDiagInfo     = { fg = "#7dcfff", bg = "#1a1b26" },
    StatusLineDiagHint     = { fg = "#9ece6a", bg = "#1a1b26" },
    StatusLineLsp          = { fg = "#565f89", bg = "#1a1b26" },
    StatusLinePos          = { fg = "#a9b1d6", bg = "#24283b" },
  }
  for name, val in pairs(colors) do
    vim.api.nvim_set_hl(0, name, val)
  end
end

setup_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("statusline_colors", { clear = true }),
  callback = setup_highlights,
})

vim.o.laststatus = 3
vim.o.statusline = "%!v:lua.require('statusline').render()"

return M
