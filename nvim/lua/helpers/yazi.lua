local M = {}

function M.open()
  local chooser_file = vim.fn.tempname()
  local cmd = string.format("yazi --chooser-file=%s %s", chooser_file, vim.fn.expand("%:p:h"))

  -- Open floating terminal
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.floor(vim.o.columns * 0.85)
  local height = math.floor(vim.o.lines * 0.85)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
  })

  vim.fn.termopen(cmd, {
    on_exit = function()
      -- Close float
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end

      -- Open chosen file
      vim.schedule(function()
        local f = io.open(chooser_file, "r")
        if f then
          local path = f:read("*l")
          f:close()
          vim.fn.delete(chooser_file)
          if path and path ~= "" then
            vim.cmd("edit " .. vim.fn.fnameescape(path))
          end
        end
      end)
    end,
  })
  vim.cmd("startinsert")
end

return M
