local M = {}

local mode_map = {
  ["n"]     = "NOR",
  ["no"]    = "O-P",
  ["nov"]   = "O-P",
  ["noV"]   = "O-P",
  ["no\22"] = "O-P",
  ["niI"]   = "NOR",
  ["niR"]   = "NOR",
  ["niV"]   = "NOR",
  ["nt"]    = "NOR",
  ["v"]     = "VIS",
  ["vs"]    = "VIS",
  ["V"]     = "V-L",
  ["Vs"]    = "V-L",
  ["\22"]   = "V-B",
  ["\22s"]  = "V-B",
  ["s"]     = "SEL",
  ["S"]     = "S-L",
  ["\19"]   = "S-B",
  ["i"]     = "INS",
  ["ic"]    = "INS",
  ["ix"]    = "INS",
  ["R"]     = "REP",
  ["Rc"]    = "REP",
  ["Rx"]    = "REP",
  ["Rv"]    = "V-R",
  ["Rvc"]   = "V-R",
  ["Rvx"]   = "V-R",
  ["c"]     = "CMD",
  ["cv"]    = "EX ",
  ["ce"]    = "EX ",
  ["r"]     = "ENT",
  ["rm"]    = "MOR",
  ["r?"]    = "CON",
  ["!"]     = "SHL",
  ["t"]     = "TRM",
}

local mode_hl = {
  NOR = "StatusLineMode",
  INS = "StatusLineModeInsert",
  VIS = "StatusLineModeVisual",
  ["V-L"] = "StatusLineModeVisual",
  ["V-B"] = "StatusLineModeVisual",
  REP = "StatusLineModeReplace",
  CMD = "StatusLineModeCommand",
  TRM = "StatusLineModeTerm",
}

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
  table.insert(parts, "%#StatusLineFile# %f %m%r%*")

  -- Git branch (from mini.diff or fallback)
  local branch = ""
  local ok, summary = pcall(function() return vim.b.minidiff_summary end)
  if ok and summary then
    branch = summary.source_name or ""
  end
  if branch == "" then
    local git_dir = vim.fn.finddir(".git", vim.fn.expand("%:p:h") .. ";")
    if git_dir ~= "" then
      local f = io.open(git_dir .. "/HEAD", "r")
      if f then
        local content = f:read("*l") or ""
        f:close()
        branch = content:match("ref: refs/heads/(.+)") or content:sub(1, 7)
      end
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

  -- LSP server name
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients > 0 then
    local names = {}
    for _, c in ipairs(clients) do
      table.insert(names, c.name)
    end
    table.insert(parts, "%#StatusLineLsp# " .. table.concat(names, ", ") .. " %*")
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
