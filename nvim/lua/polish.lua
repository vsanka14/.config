-- This will run last in the setup process.
-- This is just pure lua so anything that doesn't
-- fit in the normal config locations above can go here

-- Auto-save when leaving insert mode
vim.api.nvim_create_autocmd("InsertLeave", {
  pattern = "*",
  command = "silent! update",
  desc = "Auto-save on leaving insert mode",
})

-- Auto-refresh Neo-tree git status when Neovim regains focus
-- This fixes stale git status after external git operations (push, commit, etc.)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  pattern = "*",
  callback = function()
    if package.loaded["neo-tree.sources.manager"] then require("neo-tree.sources.manager").refresh "filesystem" end
  end,
})

-- ============================================================================
-- OpenCode File Change Tracking
-- ============================================================================
-- Track files edited by OpenCode in the current session and show notifications
-- when you open them in Neovim

-- Storage for files edited by OpenCode
_G.opencode_edited_files = _G.opencode_edited_files or {}

-- Listen for file edits from OpenCode
vim.api.nvim_create_autocmd("User", {
  pattern = "OpencodeEvent:file.edited",
  callback = function(args)
    local event = args.data and args.data.event
    if event and event.properties then
      local filepath = event.properties.file or event.properties.path
      if filepath then
        -- Normalize the path
        filepath = vim.fn.fnamemodify(filepath, ":p")
        _G.opencode_edited_files[filepath] = {
          time = os.time(),
          session_port = args.data.port,
        }
      end
    end
  end,
  desc = "Track files edited by OpenCode",
})

-- Show notification when opening an OpenCode-edited file
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function(args)
    local filepath = vim.api.nvim_buf_get_name(args.buf)
    if filepath == "" then return end

    filepath = vim.fn.fnamemodify(filepath, ":p")
    local edit_info = _G.opencode_edited_files[filepath]

    if edit_info then
      local seconds_ago = os.time() - edit_info.time
      local time_str
      if seconds_ago < 60 then
        time_str = seconds_ago .. " seconds ago"
      elseif seconds_ago < 3600 then
        time_str = math.floor(seconds_ago / 60) .. " minutes ago"
      else
        time_str = math.floor(seconds_ago / 3600) .. " hours ago"
      end

      -- Show a subtle notification
      vim.notify(
        "This file was modified by OpenCode " .. time_str,
        vim.log.levels.INFO,
        { title = "OpenCode", timeout = 3000 }
      )

      -- Add a sign in the sign column (first line)
      vim.fn.sign_define("OpenCodeEdited", { text = "", texthl = "DiagnosticInfo" })
      vim.fn.sign_place(0, "opencode_signs", "OpenCodeEdited", args.buf, { lnum = 1, priority = 10 })
    end
  end,
  desc = "Notify when opening OpenCode-edited files",
})

-- Clear tracking for a file when you save it (you've reviewed the changes)
vim.api.nvim_create_autocmd("BufWritePost", {
  callback = function(args)
    local filepath = vim.api.nvim_buf_get_name(args.buf)
    if filepath == "" then return end

    filepath = vim.fn.fnamemodify(filepath, ":p")
    if _G.opencode_edited_files[filepath] then
      _G.opencode_edited_files[filepath] = nil
      -- Remove the sign
      vim.fn.sign_unplace("opencode_signs", { buffer = args.buf })
      vim.notify("OpenCode change marker cleared", vim.log.levels.INFO, { title = "OpenCode", timeout = 2000 })
    end
  end,
  desc = "Clear OpenCode tracking on save",
})

-- Track session status changes
vim.api.nvim_create_autocmd("User", {
  pattern = "OpencodeEvent:session.idle",
  callback = function()
    local count = vim.tbl_count(_G.opencode_edited_files)
    if count > 0 then
      vim.notify(
        "OpenCode finished. " .. count .. " file(s) were modified.",
        vim.log.levels.INFO,
        { title = "OpenCode" }
      )
    end
  end,
  desc = "Notify when OpenCode session becomes idle",
})

-- Command to list all OpenCode-edited files
vim.api.nvim_create_user_command("OpencodeEdits", function()
  local files = {}
  for filepath, info in pairs(_G.opencode_edited_files) do
    local seconds_ago = os.time() - info.time
    local time_str
    if seconds_ago < 60 then
      time_str = seconds_ago .. "s ago"
    elseif seconds_ago < 3600 then
      time_str = math.floor(seconds_ago / 60) .. "m ago"
    else
      time_str = math.floor(seconds_ago / 3600) .. "h ago"
    end
    table.insert(files, { filepath = filepath, time_str = time_str, time = info.time })
  end

  if #files == 0 then
    vim.notify("No files have been edited by OpenCode in this session", vim.log.levels.INFO, { title = "OpenCode" })
    return
  end

  -- Sort by most recent
  table.sort(files, function(a, b) return a.time > b.time end)

  -- Use vim.ui.select to pick a file to open
  vim.ui.select(files, {
    prompt = "OpenCode edited files:",
    format_item = function(item) return item.time_str .. " - " .. vim.fn.fnamemodify(item.filepath, ":~:.") end,
  }, function(choice)
    if choice then vim.cmd("edit " .. vim.fn.fnameescape(choice.filepath)) end
  end)
end, { desc = "List files edited by OpenCode" })

-- Command to clear all OpenCode edit tracking
vim.api.nvim_create_user_command("OpencodeClearEdits", function()
  local count = vim.tbl_count(_G.opencode_edited_files)
  _G.opencode_edited_files = {}
  -- Clear all signs
  vim.fn.sign_unplace "opencode_signs"
  vim.notify("Cleared " .. count .. " OpenCode edit marker(s)", vim.log.levels.INFO, { title = "OpenCode" })
end, { desc = "Clear all OpenCode edit tracking" })
