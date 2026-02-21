local M = {}

local sel_bg = "#292e42"
local fill_bg = "#1a1b26"

local function setup_highlights()
  vim.api.nvim_set_hl(0, "TabLineBuf",    { fg = "#565f89", bg = fill_bg })
  vim.api.nvim_set_hl(0, "TabLineBufSel", { fg = "#c0caf5", bg = sel_bg })
  vim.api.nvim_set_hl(0, "TabLineMod",    { fg = "#e0af68", bg = fill_bg })
  vim.api.nvim_set_hl(0, "TabLineModSel", { fg = "#e0af68", bg = sel_bg })
  vim.api.nvim_set_hl(0, "TabLineSep",    { fg = sel_bg, bg = fill_bg })
  vim.api.nvim_set_hl(0, "TabLineFill",   { bg = fill_bg })
end

-- Cache for dynamically created icon highlight groups
local icon_hl_cache = {}

local function get_icon_hl(base_hl, is_sel)
  local suffix = is_sel and "_TabSel" or "_Tab"
  local hl_name = base_hl .. suffix

  if not icon_hl_cache[hl_name] then
    local existing = vim.api.nvim_get_hl(0, { name = base_hl, link = false })
    local fg = existing.fg
    if fg then
      vim.api.nvim_set_hl(0, hl_name, { fg = fg, bg = is_sel and sel_bg or fill_bg })
    else
      vim.api.nvim_set_hl(0, hl_name, { link = base_hl })
    end
    icon_hl_cache[hl_name] = true
  end

  return hl_name
end

function M.render()
  local bufs = vim.tbl_filter(function(b)
    return vim.bo[b].buflisted and vim.api.nvim_buf_is_loaded(b)
  end, vim.api.nvim_list_bufs())

  if #bufs == 0 then return "" end

  local has_mini, MiniIcons = pcall(require, "mini.icons")
  local current = vim.api.nvim_get_current_buf()
  local parts = {}

  for _, buf in ipairs(bufs) do
    local is_sel = buf == current
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
    if name == "" then name = "[No Name]" end

    -- Get icon + color from mini.icons
    local icon, icon_base_hl = "", "TabLineBuf"
    if has_mini and name ~= "[No Name]" then
      icon, icon_base_hl = MiniIcons.get("file", name)
    end

    local icon_hl = "%#" .. get_icon_hl(icon_base_hl, is_sel) .. "#"
    local buf_hl = is_sel and "%#TabLineBufSel#" or "%#TabLineBuf#"

    local mod_str = ""
    if vim.bo[buf].modified then
      local mod_hl = is_sel and "%#TabLineModSel#" or "%#TabLineMod#"
      mod_str = mod_hl .. " ⦁"
    end

    local left = is_sel and "%#TabLineSep# " or " "
    local right = is_sel and "%#TabLineSep# " or " "

    -- Active: extra right padding inside the tab background
    local inner_right = is_sel and (buf_hl .. " ") or ""

    table.insert(parts, string.format(
      "%%%dT%s%s %s %s%s%s%%T",
      buf, left, icon_hl, icon, buf_hl, name, mod_str .. inner_right .. right
    ))
  end

  return table.concat(parts, "%#TabLineFill#") .. "%#TabLineFill#%="
end

setup_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("tabline_colors", { clear = true }),
  callback = function()
    icon_hl_cache = {} -- Reset cache so highlights get recreated with new colors
    setup_highlights()
  end,
})

vim.o.showtabline = 2
vim.o.tabline = "%!v:lua.require('tabline').render()"

return M
