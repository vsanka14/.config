local M = {}

--- Copy file path with current line number to clipboard
function M.copy_path_line()
  local path = vim.fn.expand("%")
  local line = vim.fn.line(".")
  local result = path .. ":" .. line
  vim.fn.setreg("+", result)
  vim.notify("Copied: " .. result, vim.log.levels.INFO)
end

--- Copy file path with line range to clipboard (for visual mode)
function M.copy_path_lines()
  local path = vim.fn.expand("%")
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  local result = path .. ":" .. start_line .. "-" .. end_line
  vim.fn.setreg("+", result)
  vim.notify("Copied: " .. result, vim.log.levels.INFO)
end

--- Copy diagnostic on current line to clipboard (includes file path and line number)
function M.copy_diagnostic()
  local lnum = vim.fn.line(".")
  local diagnostics = vim.diagnostic.get(0, { lnum = lnum - 1 })
  if #diagnostics == 0 then
    vim.notify("No diagnostics on current line", vim.log.levels.WARN)
    return
  end
  local path = vim.fn.expand("%")
  local messages = {}
  for _, d in ipairs(diagnostics) do
    local line = d.lnum + 1
    table.insert(messages, path .. ":" .. line .. ": " .. d.message)
  end
  local result = table.concat(messages, "\n")
  vim.fn.setreg("+", result)
  vim.notify("Copied: " .. result, vim.log.levels.INFO)
end

return M
