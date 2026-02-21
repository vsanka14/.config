local M = {}

local function setup_highlights()
  vim.api.nvim_set_hl(0, "TabLineBuf",     { fg = "#565f89", bg = "#1a1b26" })
  vim.api.nvim_set_hl(0, "TabLineBufSel",  { fg = "#c0caf5", bg = "#24283b", bold = true })
  vim.api.nvim_set_hl(0, "TabLineHint",    { fg = "#7aa2f7", bg = "#1a1b26", bold = true })
  vim.api.nvim_set_hl(0, "TabLineHintSel", { fg = "#7aa2f7", bg = "#24283b", bold = true })
  vim.api.nvim_set_hl(0, "TabLineMod",     { fg = "#e0af68", bg = "#1a1b26" })
  vim.api.nvim_set_hl(0, "TabLineModSel",  { fg = "#e0af68", bg = "#24283b" })
  vim.api.nvim_set_hl(0, "TabLineFill",    { bg = "#1a1b26" })
end

function M.render()
  local bufs = vim.tbl_filter(function(b)
    return vim.bo[b].buflisted and vim.api.nvim_buf_is_loaded(b)
  end, vim.api.nvim_list_bufs())

  if #bufs == 0 then return "" end

  local current = vim.api.nvim_get_current_buf()
  local parts = {}

  for _, buf in ipairs(bufs) do
    local is_current = buf == current
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
    if name == "" then name = "[No Name]" end
    local modified = vim.bo[buf].modified

    local buf_hl = is_current and "%#TabLineBufSel#" or "%#TabLineBuf#"
    local mod_hl = is_current and "%#TabLineModSel#" or "%#TabLineMod#"
    local mod_indicator = modified and (mod_hl .. " +") or ""

    -- Make clickable: %<nr>T ... %T
    table.insert(parts, string.format(
      "%%%dT%s %s%s %%T",
      buf, buf_hl, name, mod_indicator
    ))
  end

  return table.concat(parts, "%#TabLineFill# ") .. "%#TabLineFill#%="
end

setup_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("tabline_colors", { clear = true }),
  callback = setup_highlights,
})

vim.o.showtabline = 2
vim.o.tabline = "%!v:lua.require('tabline').render()"

return M
