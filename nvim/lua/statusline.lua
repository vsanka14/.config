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

-- LSP progress tracking
local lsp_progress = {}

vim.api.nvim_create_autocmd("LspProgress", {
  group = vim.api.nvim_create_augroup("statusline_lsp_progress", { clear = true }),
  callback = function(args)
    local data = args.data
    if not data or not data.params then return end
    local val = data.params.value
    local client_id = data.client_id
    if not val or not client_id then return end

    if val.kind == "end" then
      lsp_progress[client_id] = nil
    else
      local msg = val.title or ""
      if val.message then msg = msg .. ": " .. val.message end
      if val.percentage then msg = msg .. " (" .. val.percentage .. "%%%%)" end
      lsp_progress[client_id] = msg
    end
    vim.cmd.redrawstatus()
  end,
})

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

function M.render()
  local mode = vim.api.nvim_get_mode().mode
  local mode_label = mode_map[mode] or mode
  local hl = mode_hl[mode_label] or "StatusLineMode"

  -- Mode
  local parts = { "%#" .. hl .. "# " .. mode_label .. " %*" }

  -- File
  table.insert(parts, "%#StatusLineFile# %t %m%r%*")

  -- Git branch
  local branch = ""
  local buf_dir = vim.fn.expand("%:p:h")
  if buf_dir ~= "" then
    local result = vim.fn.systemlist("git -C " .. vim.fn.shellescape(buf_dir) .. " rev-parse --abbrev-ref HEAD 2>/dev/null")
    if vim.v.shell_error == 0 and result[1] and result[1] ~= "" then
      branch = result[1]
    end
  end
  if branch ~= "" then
    table.insert(parts, "%#StatusLineGit#  " .. branch .. " %*")
  end

  -- Separator
  table.insert(parts, "%=")

  -- Diagnostics
  local diag_counts = {
    { vim.diagnostic.severity.ERROR, "StatusLineDiagError", " " },
    { vim.diagnostic.severity.WARN,  "StatusLineDiagWarn",  " " },
    { vim.diagnostic.severity.INFO,  "StatusLineDiagInfo",  " " },
    { vim.diagnostic.severity.HINT,  "StatusLineDiagHint",  " " },
  }
  for _, d in ipairs(diag_counts) do
    local count = #vim.diagnostic.get(0, { severity = d[1] })
    if count > 0 then
      table.insert(parts, "%#" .. d[2] .. "#" .. d[3] .. count .. " %*")
    end
  end

  -- LSP progress or server name
  local progress_msgs = {}
  for _, msg in pairs(lsp_progress) do
    table.insert(progress_msgs, msg)
  end
  if #progress_msgs > 0 then
    table.insert(parts, "%#StatusLineLsp# " .. table.concat(progress_msgs, " | ") .. " %*")
  else
    local clients = vim.lsp.get_clients({ bufnr = 0 })
    if #clients > 0 then
      local names = {}
      for _, c in ipairs(clients) do
        table.insert(names, c.name)
      end
      table.insert(parts, "%#StatusLineLsp# " .. table.concat(names, ", ") .. " %*")
    end
  end

  -- Position + filetype
  table.insert(parts, "%#StatusLinePos# %l:%c %p%% %*")

  return table.concat(parts)
end

-- Set up highlights and statusline
setup_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("statusline_colors", { clear = true }),
  callback = setup_highlights,
})

-- Use global statusline
vim.o.laststatus = 3
vim.o.statusline = "%!v:lua.require('statusline').render()"

return M
