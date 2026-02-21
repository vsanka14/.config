-- Trino query execution module for Neovim
-- Commands: TrinoRun, TrinoRunSelection, TrinoCluster, TrinoCancel, TrinoAuthUser, TrinoClearCache, TrinoClear, TrinoNext, TrinoPrev

local M = {}

-- ============================================================================
-- Constants
-- ============================================================================
local CREDENTIAL_CACHE_TTL = 900

-- ============================================================================
-- State Management
-- ============================================================================
local state = {
  cluster = "holdem",
  start_time = nil,
  loading_notif_id = nil,
  cached_password = nil,
  cached_otp = nil,
  cached_auth_user = "convtrack",
  cache_timestamp = nil,
  current_job = nil,
  cancelled = false,
  failed_queries = {},
  total_queries = 0,
  completed_count = 0,
  result_buffers = {},
  result_win = nil,
  split_height_pct = 50,
}

-- ============================================================================
-- Credential Caching
-- ============================================================================

local function is_cache_valid()
  if not state.cached_password or not state.cached_otp or not state.cache_timestamp then
    return false
  end
  return (os.time() - state.cache_timestamp) < CREDENTIAL_CACHE_TTL
end

local function invalidate_credential_cache()
  state.cached_password = nil
  state.cached_otp = nil
  state.cache_timestamp = nil
end

local function get_credentials()
  if is_cache_valid() then
    local remaining = CREDENTIAL_CACHE_TTL - (os.time() - state.cache_timestamp)
    vim.notify(string.format("Using cached credentials (%ds remaining)", remaining), vim.log.levels.INFO, { title = "Trino" })
    return state.cached_password, state.cached_otp, state.cached_auth_user
  end

  local password = vim.fn.inputsecret("Trino [" .. state.cluster .. "] - Password: ")
  if not password or password == "" then return nil, nil, nil end

  local otp = vim.fn.inputsecret("Trino [" .. state.cluster .. "] - OKTA code: ")
  if not otp or otp == "" then return nil, nil, nil end

  state.cached_password = password
  state.cached_otp = otp
  state.cache_timestamp = os.time()

  return password, otp, state.cached_auth_user
end

local function clear_credential_cache()
  state.cached_password = nil
  state.cached_otp = nil
  state.cached_auth_user = "convtrack"
  state.cache_timestamp = nil
  vim.notify("Credential cache cleared", vim.log.levels.INFO, { title = "Trino" })
end

-- ============================================================================
-- SQL Extraction Helpers
-- ============================================================================

local function get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
  return table.concat(lines, "\n")
end

local function get_buffer_content()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return table.concat(lines, "\n")
end

-- ============================================================================
-- SQL Parsing with Tree-sitter
-- ============================================================================

local function split_queries(sql)
  local ok, parser = pcall(vim.treesitter.get_string_parser, sql, "sql")
  if not ok then
    vim.notify("SQL Tree-sitter parser not available. Run :TSInstall sql", vim.log.levels.ERROR, { title = "Trino" })
    return {}
  end

  local trees = parser:parse()
  if not trees or #trees == 0 then return {} end

  local root = trees[1]:root()
  local queries = {}

  for i = 0, root:named_child_count() - 1 do
    local node = root:named_child(i)
    if node:type() == "statement" then
      local text = vim.trim(vim.treesitter.get_node_text(node, sql))
      if not text:match(";$") then text = text .. ";" end
      table.insert(queries, { index = #queries + 1, text = text })
    end
  end

  return queries
end

-- ============================================================================
-- Notification Helpers
-- ============================================================================

local function show_loading_notification(message)
  vim.notify(message, vim.log.levels.INFO, { title = "Trino" })
end

local function dismiss_loading_notification()
  -- mini.notify handles auto-dismiss
end

-- ============================================================================
-- Result Buffer Management
-- ============================================================================

local function is_result_win_valid()
  return state.result_win and vim.api.nvim_win_is_valid(state.result_win)
end

local function create_result_buffer(index, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  if buf == 0 then
    vim.notify("Failed to create result buffer", vim.log.levels.ERROR, { title = "Trino" })
    return
  end

  pcall(vim.api.nvim_buf_set_name, buf, string.format("trino://results/%d", index))

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "csv"

  table.insert(state.result_buffers, { buf = buf, index = index })
end

local function get_result_winbar()
  if #state.result_buffers == 0 then return "" end
  if not is_result_win_valid() then return "" end

  local current_buf = vim.api.nvim_win_get_buf(state.result_win)
  local parts = {}

  for i, entry in ipairs(state.result_buffers) do
    local is_current = entry.buf == current_buf
    local hl = is_current and "%#TabLineSel#" or "%#TabLine#"
    table.insert(parts, string.format("%%%d@v:lua.TrinoSelectResult@%s %d %%X%%*", i, hl, entry.index))
  end

  return table.concat(parts, "%#TabLineFill#|")
end

local function refresh_result_winbar()
  if is_result_win_valid() then
    vim.wo[state.result_win].winbar = get_result_winbar()
  end
end

local function enable_csvview_on_result()
  vim.schedule(function()
    if not is_result_win_valid() then return end

    local ok, csvview = pcall(require, "csvview")
    if not ok then return end

    local current_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(state.result_win)

    if csvview.is_enabled() then csvview.disable() end
    csvview.enable()

    vim.api.nvim_set_current_win(current_win)
  end)
end

local function switch_to_result(index)
  if not is_result_win_valid() then return end
  local entry = state.result_buffers[index]
  if entry and vim.api.nvim_buf_is_valid(entry.buf) then
    vim.api.nvim_win_set_buf(state.result_win, entry.buf)
    refresh_result_winbar()
    enable_csvview_on_result()
  end
end

-- Global click handler for winbar tabs
_G.TrinoSelectResult = function(minwid) switch_to_result(minwid) end

local function clear_result_buffers()
  if is_result_win_valid() then
    vim.api.nvim_win_close(state.result_win, true)
  end
  state.result_win = nil

  for _, entry in ipairs(state.result_buffers) do
    if vim.api.nvim_buf_is_valid(entry.buf) then
      pcall(vim.api.nvim_buf_delete, entry.buf, { force = true })
    end
  end
  state.result_buffers = {}
end

local function get_current_result_index()
  if not is_result_win_valid() then return nil end
  local current_buf = vim.api.nvim_win_get_buf(state.result_win)
  for i, entry in ipairs(state.result_buffers) do
    if entry.buf == current_buf then return i end
  end
  return nil
end

local function open_result_split()
  if #state.result_buffers == 0 then return end

  local first_entry = state.result_buffers[1]
  if not vim.api.nvim_buf_is_valid(first_entry.buf) then return end

  if is_result_win_valid() then
    vim.api.nvim_win_set_buf(state.result_win, first_entry.buf)
    refresh_result_winbar()
    enable_csvview_on_result()
    return
  end

  local origin_win = vim.api.nvim_get_current_win()
  local split_height = math.floor(vim.o.lines * state.split_height_pct / 100)

  vim.cmd(string.format("botright %dsplit", split_height))
  state.result_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.result_win, first_entry.buf)

  refresh_result_winbar()
  enable_csvview_on_result()

  if origin_win and vim.api.nvim_win_is_valid(origin_win) then
    vim.api.nvim_set_current_win(origin_win)
  end
end

local function trino_next_result()
  if #state.result_buffers == 0 then
    vim.notify("No result buffers available", vim.log.levels.WARN, { title = "Trino" })
    return
  end
  if not is_result_win_valid() then
    open_result_split()
    return
  end
  local current_idx = get_current_result_index() or 0
  switch_to_result((current_idx % #state.result_buffers) + 1)
end

local function trino_prev_result()
  if #state.result_buffers == 0 then
    vim.notify("No result buffers available", vim.log.levels.WARN, { title = "Trino" })
    return
  end
  if not is_result_win_valid() then
    open_result_split()
    return
  end
  local current_idx = get_current_result_index() or 1
  switch_to_result(((current_idx - 2) % #state.result_buffers) + 1)
end

-- ============================================================================
-- Query Execution
-- ============================================================================

local function write_file(path, content)
  local f = io.open(path, "w")
  if f then
    f:write(content)
    f:close()
    return true
  end
  return false
end

local function read_file_lines(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local lines = {}
  for line in f:lines() do
    table.insert(lines, line)
  end
  f:close()
  return lines
end

local function run_single_query(query_info, password, otp, auth_user, on_complete)
  local query_file = "/tmp/trino_query.sql"
  local temp_output_file = "/tmp/trino_output.csv"
  local temp_stderr_file = "/tmp/trino_stderr.txt"

  if not write_file(query_file, query_info.text) then
    on_complete(false, "Failed to write query file", nil)
    return
  end

  vim.fn.delete(temp_output_file)
  vim.fn.delete(temp_stderr_file)

  local cmd = {
    "sh", "-c",
    string.format(
      "trino query -c %s -f %s --session li_authorization_user=%s --output-format CSV_HEADER > %s 2> %s",
      state.cluster, query_file, auth_user, temp_output_file, temp_stderr_file
    ),
  }

  local job_id = vim.fn.jobstart(cmd, {
    stdin = "pipe",
    on_exit = function(_, exit_code)
      vim.schedule(function()
        state.current_job = nil

        local stderr_lines = read_file_lines(temp_stderr_file) or {}
        local stderr_content = table.concat(stderr_lines, "\n")
        vim.fn.delete(temp_stderr_file)

        if stderr_content:match("LDAP") or stderr_content:match("[Aa]uthentication failed") then
          invalidate_credential_cache()
          vim.notify("Authentication failed. Credentials cleared for retry.", vim.log.levels.WARN, { title = "Trino" })
        end

        local function extract_error(content)
          local error_start = content:match("(Query [%w_]+ failed.*)$")
            or content:match("(FAILED.*)$")
            or content:match("(Error:.*)$")
            or content:match("(LDAP.*)$")
            or content:match("([Aa]uthentication failed.*)$")
          return error_start or content
        end

        local has_error = exit_code ~= 0
          or stderr_content:match("Query [%w_]+ failed")
          or stderr_content:match("FAILED")
          or stderr_content:match("LDAP")
          or stderr_content:match("[Aa]uthentication failed")

        if has_error then
          vim.fn.delete(temp_output_file)
          on_complete(false, stderr_content ~= "" and extract_error(stderr_content) or "Unknown error", nil)
        else
          local csv_lines = read_file_lines(temp_output_file)
          vim.fn.delete(temp_output_file)
          if (not csv_lines or #csv_lines == 0) and stderr_content ~= "" then
            on_complete(false, extract_error(stderr_content), nil)
          else
            on_complete(true, nil, csv_lines or {})
          end
        end
      end)
    end,
  })

  if job_id <= 0 then
    on_complete(false, "Failed to start job", nil)
    return
  end

  state.current_job = job_id
  vim.fn.chansend(job_id, password .. "\n")
  vim.fn.chansend(job_id, otp .. "\n")
  vim.fn.chanclose(job_id, "stdin")
end

local function run_queries_sequentially(queries, password, otp, auth_user, on_all_complete)
  if #queries == 0 then
    on_all_complete()
    return
  end

  state.total_queries = #queries
  state.completed_count = 0
  state.failed_queries = {}

  local current_index = 1

  local function run_next()
    if state.cancelled or current_index > #queries then
      on_all_complete()
      return
    end

    local query_info = queries[current_index]

    show_loading_notification(string.format(
      "Query %d/%d on %s...",
      state.completed_count + 1, state.total_queries, state.cluster
    ))

    run_single_query(query_info, password, otp, auth_user, function(success, error_msg, csv_lines)
      if state.cancelled then
        run_next()
        return
      end

      state.completed_count = state.completed_count + 1
      if not success then
        table.insert(state.failed_queries, { index = query_info.index, error = error_msg })
        create_result_buffer(query_info.index, vim.split(error_msg or "Unknown error", "\n"))
      else
        create_result_buffer(query_info.index, csv_lines)
      end

      if not is_result_win_valid() then
        open_result_split()
      else
        refresh_result_winbar()
      end

      current_index = current_index + 1
      run_next()
    end)
  end

  run_next()
end

local function show_results()
  dismiss_loading_notification()

  if state.cancelled then
    local success_count = state.total_queries - #state.failed_queries - (state.total_queries - state.completed_count)
    local cancelled_count = state.total_queries - state.completed_count
    vim.notify(
      string.format("%d/%d queries completed, %d cancelled", success_count, state.total_queries, cancelled_count),
      vim.log.levels.WARN, { title = "Trino [" .. state.cluster .. "]" }
    )
    state.total_queries = 0
    return
  end

  local success_count = state.total_queries - #state.failed_queries
  local failed_count = #state.failed_queries

  local elapsed = ""
  if state.start_time then
    local elapsed_ms = (vim.loop.hrtime() - state.start_time) / 1e6
    if elapsed_ms > 1000 then
      elapsed = string.format(" (%.1fs)", elapsed_ms / 1000)
    else
      elapsed = string.format(" (%dms)", elapsed_ms)
    end
  end

  local msg
  if state.total_queries == 0 then
    msg = "No data queries to execute"
  elseif failed_count == 0 then
    msg = string.format("%d/%d queries completed%s", success_count, state.total_queries, elapsed)
  else
    msg = string.format("%d/%d queries completed, %d failed%s", success_count, state.total_queries, failed_count, elapsed)
  end

  vim.notify(msg, failed_count > 0 and vim.log.levels.WARN or vim.log.levels.INFO, { title = "Trino [" .. state.cluster .. "]" })
end

local function execute_trino_query(sql)
  if not sql or sql:match("^%s*$") then
    vim.notify("No SQL to execute", vim.log.levels.WARN, { title = "Trino" })
    return
  end

  if state.current_job then
    vim.notify("Query already running. Cancel it first with :TrinoCancel", vim.log.levels.WARN, { title = "Trino" })
    return
  end

  local queries = split_queries(sql)
  if #queries == 0 then
    vim.notify("No valid SQL queries found", vim.log.levels.WARN, { title = "Trino" })
    return
  end

  local password, otp, auth_user = get_credentials()
  if not password or not otp or not auth_user then
    vim.notify("Query cancelled - credentials not provided", vim.log.levels.WARN, { title = "Trino" })
    return
  end

  clear_result_buffers()
  state.cancelled = false
  state.start_time = vim.loop.hrtime()
  show_loading_notification(string.format("Executing queries on %s...", state.cluster))

  run_queries_sequentially(queries, password, otp, auth_user, function()
    show_results()
  end)
end

-- ============================================================================
-- Public Commands
-- ============================================================================

local function trino_run()
  if vim.bo.filetype ~= "sql" then
    vim.notify("TrinoRun only works in .sql files", vim.log.levels.WARN, { title = "Trino" })
    return
  end
  execute_trino_query(get_buffer_content())
end

local function trino_run_selection()
  if vim.bo.filetype ~= "sql" then
    vim.notify("TrinoRunSelection only works in .sql files", vim.log.levels.WARN, { title = "Trino" })
    return
  end
  execute_trino_query(get_visual_selection())
end

local function trino_cluster(args)
  local cluster = args.args
  if cluster and cluster ~= "" then
    local valid_clusters = { holdem = true, war = true, faro = true }
    if valid_clusters[cluster] then
      state.cluster = cluster
      vim.notify("Trino cluster set to: " .. cluster, vim.log.levels.INFO, { title = "Trino" })
    else
      vim.notify("Invalid cluster. Use: holdem, war, or faro", vim.log.levels.ERROR, { title = "Trino" })
    end
  else
    vim.ui.select({ "holdem", "war", "faro" }, {
      prompt = "Select Trino cluster:",
      format_item = function(item)
        return item .. (item == state.cluster and " (current)" or "")
      end,
    }, function(choice)
      if choice then
        state.cluster = choice
        vim.notify("Trino cluster set to: " .. choice, vim.log.levels.INFO, { title = "Trino" })
      end
    end)
  end
end

local function trino_cancel()
  if not state.current_job and state.total_queries == 0 then
    vim.notify("No running query to cancel", vim.log.levels.WARN, { title = "Trino" })
    return
  end
  state.cancelled = true
  if state.current_job then
    vim.fn.jobstop(state.current_job)
    state.current_job = nil
  end
  state.start_time = nil
  dismiss_loading_notification()
end

local function trino_auth_user(args)
  local user = args.args
  if user and user ~= "" then
    state.cached_auth_user = user
    state.cache_timestamp = os.time()
    vim.notify("Auth user set to: " .. user, vim.log.levels.INFO, { title = "Trino" })
  else
    vim.ui.input({
      prompt = "Auth user (li_authorization_user): ",
      default = state.cached_auth_user or "",
    }, function(input)
      if input and input ~= "" then
        state.cached_auth_user = input
        state.cache_timestamp = os.time()
        vim.notify("Auth user set to: " .. input, vim.log.levels.INFO, { title = "Trino" })
      end
    end)
  end
end

-- ============================================================================
-- Setup: register commands and SQL-file keymaps
-- ============================================================================

function M.setup()
  -- User commands
  vim.api.nvim_create_user_command("TrinoRun", trino_run, { desc = "Run current SQL buffer against Trino" })
  vim.api.nvim_create_user_command("TrinoRunSelection", trino_run_selection, { desc = "Run visual selection against Trino" })
  vim.api.nvim_create_user_command("TrinoCluster", trino_cluster, {
    nargs = "?",
    complete = function() return { "holdem", "war", "faro" } end,
    desc = "Set Trino cluster",
  })
  vim.api.nvim_create_user_command("TrinoCancel", trino_cancel, { desc = "Cancel running Trino query" })
  vim.api.nvim_create_user_command("TrinoAuthUser", trino_auth_user, {
    nargs = "?",
    desc = "Set Trino authorization user",
  })
  vim.api.nvim_create_user_command("TrinoClearCache", clear_credential_cache, { desc = "Clear cached Trino credentials" })
  vim.api.nvim_create_user_command("TrinoClear", clear_result_buffers, { desc = "Clear all Trino result buffers" })
  vim.api.nvim_create_user_command("TrinoNext", trino_next_result, { desc = "Next Trino result buffer" })
  vim.api.nvim_create_user_command("TrinoPrev", trino_prev_result, { desc = "Previous Trino result buffer" })

  -- SQL file keymaps
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "sql",
    callback = function(args)
      local bufnr = args.buf
      local map = function(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
      end

      map("n", "<Leader>qr", trino_run, "Trino: Run query")
      map("v", "<Leader>qr", function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
        vim.schedule(trino_run_selection)
      end, "Trino: Run selection")
      map("n", "<Leader>qc", function() trino_cluster({ args = "" }) end, "Trino: Change cluster")
      map("n", "<Leader>qu", function() trino_auth_user({ args = "" }) end, "Trino: Change auth user")
      map("n", "<Leader>qx", trino_cancel, "Trino: Cancel query")
      map("n", "<Leader>qC", clear_result_buffers, "Trino: Clear result buffers")
      map("n", "<Leader>qn", trino_next_result, "Trino: Next result")
      map("n", "<Leader>qp", trino_prev_result, "Trino: Previous result")
    end,
    desc = "Set up Trino keymaps for SQL files",
  })
end

return M
