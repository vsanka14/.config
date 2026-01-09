-- Trino query execution plugin for Neovim
-- Executes SQL queries against LinkedIn's Trino clusters and displays results
-- Features:
--   - Tree-sitter based SQL parsing for multi-query support
--   - Sequential query execution
--   - Credential caching with TTL
--   - Loading indicator via Snacks.notifier
--   - Results displayed in a single split window with csvview.nvim rendering
--   - Multiple results navigable via <Leader>qn/<Leader>qp within the split
--   - Commands: TrinoRun, TrinoRunSelection, TrinoCluster, TrinoCancel,
--               TrinoAuthUser, TrinoClearCache, TrinoClear, TrinoNext, TrinoPrev

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = function(_, opts)
    -- ============================================================================
    -- Constants
    -- ============================================================================
    local CREDENTIAL_CACHE_TTL = 900 -- 15 minutes

    -- ============================================================================
    -- State Management
    -- ============================================================================
    local trino_state = {
      cluster = "holdem", -- default cluster: holdem, war, faro
      start_time = nil, -- query start time for elapsed calculation
      loading_notif_id = nil, -- loading notification ID for dismissal

      -- Credential cache
      cached_password = nil,
      cached_otp = nil,
      cached_auth_user = "convtrack", -- li_authorization_user
      cache_timestamp = nil,

      -- Job tracking
      current_job = nil, -- current running job ID
      failed_queries = {}, -- { { index=1, error="..." }, ... }
      total_queries = 0,
      completed_count = 0,

      -- Result buffer tracking
      result_buffers = {}, -- buffer IDs for cleanup
      result_win = nil, -- window ID for result split
      split_height_pct = 50, -- percentage of screen height for splits
    }

    -- ============================================================================
    -- Credential Caching
    -- ============================================================================

    local function is_cache_valid()
      if not trino_state.cached_password or not trino_state.cached_otp or not trino_state.cache_timestamp then
        return false
      end
      local elapsed = os.time() - trino_state.cache_timestamp
      return elapsed < CREDENTIAL_CACHE_TTL
    end

    local function get_credentials()
      if is_cache_valid() then
        local remaining = CREDENTIAL_CACHE_TTL - (os.time() - trino_state.cache_timestamp)
        vim.notify(
          string.format("Using cached credentials (%ds remaining)", remaining),
          vim.log.levels.INFO,
          { title = "Trino" }
        )
        return trino_state.cached_password, trino_state.cached_otp, trino_state.cached_auth_user
      end

      local password = vim.fn.inputsecret("Trino [" .. trino_state.cluster .. "] - Password: ")
      if not password or password == "" then return nil, nil, nil end

      local otp = vim.fn.inputsecret("Trino [" .. trino_state.cluster .. "] - OKTA code: ")
      if not otp or otp == "" then return nil, nil, nil end

      trino_state.cached_password = password
      trino_state.cached_otp = otp
      trino_state.cache_timestamp = os.time()

      return password, otp, trino_state.cached_auth_user
    end

    local function clear_credential_cache()
      trino_state.cached_password = nil
      trino_state.cached_otp = nil
      trino_state.cached_auth_user = "convtrack" -- Reset to default
      trino_state.cache_timestamp = nil
      vim.notify("Credential cache cleared", vim.log.levels.INFO, { title = "Trino" })
    end

    -- ============================================================================
    -- SQL Extraction Helpers
    -- ============================================================================

    local function get_visual_selection()
      local start_pos = vim.fn.getpos "'<"
      local end_pos = vim.fn.getpos "'>"
      local start_line = start_pos[2]
      local end_line = end_pos[2]
      local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
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
        vim.notify(
          "SQL Tree-sitter parser not available. Run :TSInstall sql",
          vim.log.levels.ERROR,
          { title = "Trino" }
        )
        return {}
      end

      local trees = parser:parse()
      if not trees or #trees == 0 then return {} end

      local root = trees[1]:root()
      local queries = {}
      local query_index = 0

      for i = 0, root:named_child_count() - 1 do
        local node = root:named_child(i)
        if node:type() == "statement" then
          local text = vim.treesitter.get_node_text(node, sql)
          text = vim.trim(text)
          if not text:match ";$" then text = text .. ";" end

          query_index = query_index + 1
          table.insert(queries, { index = query_index, text = text })
        end
      end

      return queries
    end

    -- ============================================================================
    -- Notification Helpers
    -- ============================================================================

    local function show_loading_notification(message)
      local ok, Snacks = pcall(require, "snacks")
      if ok and Snacks.notifier then
        trino_state.loading_notif_id = Snacks.notifier.notify(message, vim.log.levels.INFO, {
          title = "Trino",
          timeout = false,
          icon = "󰑮",
        })
      else
        vim.notify(message, vim.log.levels.INFO, { title = "Trino" })
      end
    end

    local function update_loading_notification(message)
      local ok, Snacks = pcall(require, "snacks")
      if ok and Snacks.notifier and trino_state.loading_notif_id then
        Snacks.notifier.hide(trino_state.loading_notif_id)
        trino_state.loading_notif_id = Snacks.notifier.notify(message, vim.log.levels.INFO, {
          title = "Trino",
          timeout = false,
          icon = "󰑮",
        })
      end
    end

    local function dismiss_loading_notification()
      if trino_state.loading_notif_id then
        local ok, Snacks = pcall(require, "snacks")
        if ok and Snacks.notifier then Snacks.notifier.hide(trino_state.loading_notif_id) end
        trino_state.loading_notif_id = nil
      end
    end

    -- ============================================================================
    -- Result Buffer Management
    -- ============================================================================

    local function create_result_buffer(index, csv_lines)
      local buf = vim.api.nvim_create_buf(false, true)
      if buf == 0 then
        vim.notify("Failed to create result buffer", vim.log.levels.ERROR, { title = "Trino" })
        return
      end

      pcall(vim.api.nvim_buf_set_name, buf, string.format("trino://results/%d", index))

      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].bufhidden = "hide"
      vim.bo[buf].swapfile = false

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, csv_lines)
      vim.bo[buf].modifiable = false
      vim.bo[buf].filetype = "csv"

      table.insert(trino_state.result_buffers, buf)
    end

    local function get_result_winbar()
      if #trino_state.result_buffers == 0 then return "" end
      if not trino_state.result_win or not vim.api.nvim_win_is_valid(trino_state.result_win) then
        return ""
      end

      local current_buf = vim.api.nvim_win_get_buf(trino_state.result_win)
      local parts = {}

      for i, buf in ipairs(trino_state.result_buffers) do
        local hl = (buf == current_buf) and "%#TabLineSel#" or "%#TabLine#"
        table.insert(parts, string.format("%%%d@v:lua.TrinoSelectResult@%s %d %%X%%*", i, hl, i))
      end

      return table.concat(parts, "%#TabLineFill#│")
    end

    local function refresh_result_winbar()
      if trino_state.result_win and vim.api.nvim_win_is_valid(trino_state.result_win) then
        vim.wo[trino_state.result_win].winbar = get_result_winbar()
      end
    end

    local function enable_csvview_on_result()
      if not trino_state.result_win or not vim.api.nvim_win_is_valid(trino_state.result_win) then
        return
      end

      vim.schedule(function()
        if not trino_state.result_win or not vim.api.nvim_win_is_valid(trino_state.result_win) then
          return
        end

        local ok, csvview = pcall(require, "csvview")
        if not ok then return end

        local current_win = vim.api.nvim_get_current_win()
        vim.api.nvim_set_current_win(trino_state.result_win)

        if csvview.is_enabled() then csvview.disable() end
        csvview.enable()

        vim.api.nvim_set_current_win(current_win)
      end)
    end

    local function switch_to_result(index)
      if not trino_state.result_win or not vim.api.nvim_win_is_valid(trino_state.result_win) then
        return
      end

      local buf = trino_state.result_buffers[index]
      if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_win_set_buf(trino_state.result_win, buf)
        refresh_result_winbar()
        enable_csvview_on_result()
      end
    end

    -- Global click handler for winbar tabs
    _G.TrinoSelectResult = function(minwid) switch_to_result(minwid) end

    local function clear_result_buffers()
      if trino_state.result_win and vim.api.nvim_win_is_valid(trino_state.result_win) then
        vim.api.nvim_win_close(trino_state.result_win, true)
      end
      trino_state.result_win = nil

      for _, buf in ipairs(trino_state.result_buffers) do
        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
      trino_state.result_buffers = {}
    end

    local function get_current_result_index()
      if not trino_state.result_win or not vim.api.nvim_win_is_valid(trino_state.result_win) then
        return nil
      end

      local current_buf = vim.api.nvim_win_get_buf(trino_state.result_win)
      for i, buf in ipairs(trino_state.result_buffers) do
        if buf == current_buf then return i end
      end
      return nil
    end

    local function open_result_split()
      if #trino_state.result_buffers == 0 then return end

      local first_buf = trino_state.result_buffers[1]
      if not vim.api.nvim_buf_is_valid(first_buf) then return end

      if trino_state.result_win and vim.api.nvim_win_is_valid(trino_state.result_win) then
        vim.api.nvim_win_set_buf(trino_state.result_win, first_buf)
        refresh_result_winbar()
        enable_csvview_on_result()
        return
      end

      local origin_win = vim.api.nvim_get_current_win()
      local split_height = math.floor(vim.o.lines * trino_state.split_height_pct / 100)

      vim.cmd(string.format("botright %dsplit", split_height))
      trino_state.result_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(trino_state.result_win, first_buf)

      refresh_result_winbar()
      enable_csvview_on_result()

      if origin_win and vim.api.nvim_win_is_valid(origin_win) then
        vim.api.nvim_set_current_win(origin_win)
      end
    end

    local function trino_next_result()
      if #trino_state.result_buffers == 0 then
        vim.notify("No result buffers available", vim.log.levels.WARN, { title = "Trino" })
        return
      end

      if not trino_state.result_win or not vim.api.nvim_win_is_valid(trino_state.result_win) then
        open_result_split()
        return
      end

      local current_idx = get_current_result_index() or 0
      local next_idx = (current_idx % #trino_state.result_buffers) + 1
      switch_to_result(next_idx)
    end

    local function trino_prev_result()
      if #trino_state.result_buffers == 0 then
        vim.notify("No result buffers available", vim.log.levels.WARN, { title = "Trino" })
        return
      end

      if not trino_state.result_win or not vim.api.nvim_win_is_valid(trino_state.result_win) then
        open_result_split()
        return
      end

      local current_idx = get_current_result_index() or 1
      local prev_idx = ((current_idx - 2) % #trino_state.result_buffers) + 1
      switch_to_result(prev_idx)
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
      local stderr_chunks = {}

      if not write_file(query_file, query_info.text) then
        on_complete(false, "Failed to write query file", nil)
        return
      end

      vim.fn.delete(temp_output_file)

      local cmd = {
        "sh",
        "-c",
        string.format(
          "trino query -c %s -f %s --session li_authorization_user=%s --output-format CSV_HEADER > %s",
          trino_state.cluster,
          query_file,
          auth_user,
          temp_output_file
        ),
      }

      local job_id = vim.fn.jobstart(cmd, {
        stdin = "pipe",
        on_stderr = function(_, data)
          if data then
            for _, line in ipairs(data) do
              if line ~= "" then table.insert(stderr_chunks, line) end
            end
          end
        end,
        on_exit = function(_, exit_code)
          vim.schedule(function()
            trino_state.current_job = nil

            local stderr_content = table.concat(stderr_chunks, "\n")
            local has_error = exit_code ~= 0
              or stderr_content:match "Query %w+ failed"
              or stderr_content:match "FAILED"

            if has_error then
              vim.fn.delete(temp_output_file)
              local error_msg = stderr_content ~= "" and stderr_content:sub(1, 200) or "Unknown error"
              on_complete(false, error_msg, nil)
            else
              local csv_lines = read_file_lines(temp_output_file)
              vim.fn.delete(temp_output_file)
              on_complete(true, nil, csv_lines or {})
            end
          end)
        end,
      })

      if job_id <= 0 then
        on_complete(false, "Failed to start job", nil)
        return
      end

      trino_state.current_job = job_id

      vim.fn.chansend(job_id, password .. "\n")
      vim.fn.chansend(job_id, otp .. "\n")
      vim.fn.chanclose(job_id, "stdin")
    end

    local function run_queries_sequentially(queries, password, otp, auth_user, on_all_complete)
      if #queries == 0 then
        on_all_complete()
        return
      end

      trino_state.total_queries = #queries
      trino_state.completed_count = 0
      trino_state.failed_queries = {}

      local current_index = 1

      local function run_next()
        if current_index > #queries then
          on_all_complete()
          return
        end

        local query_info = queries[current_index]

        update_loading_notification(
          string.format(
            "Query %d/%d on %s...",
            trino_state.completed_count + 1,
            trino_state.total_queries,
            trino_state.cluster
          )
        )

        run_single_query(query_info, password, otp, auth_user, function(success, error_msg, csv_lines)
          trino_state.completed_count = trino_state.completed_count + 1
          if not success then
            table.insert(trino_state.failed_queries, { index = query_info.index, error = error_msg })
          else
            create_result_buffer(query_info.index, csv_lines)
          end

          current_index = current_index + 1
          run_next()
        end)
      end

      run_next()
    end

    local function show_results()
      dismiss_loading_notification()

      local success_count = trino_state.total_queries - #trino_state.failed_queries

      local elapsed = ""
      if trino_state.start_time then
        local elapsed_ms = (vim.loop.hrtime() - trino_state.start_time) / 1e6
        if elapsed_ms > 1000 then
          elapsed = string.format(" (%.1fs)", elapsed_ms / 1000)
        else
          elapsed = string.format(" (%dms)", elapsed_ms)
        end
      end

      local msg
      if trino_state.total_queries == 0 then
        msg = "No data queries to execute"
      elseif #trino_state.failed_queries == 0 then
        msg = string.format("%d/%d queries completed%s", success_count, trino_state.total_queries, elapsed)
      else
        msg = string.format(
          "%d/%d queries completed%s\nFailed: %s",
          success_count,
          trino_state.total_queries,
          elapsed,
          table.concat(
            vim.tbl_map(function(q) return string.format("#%d", q.index) end, trino_state.failed_queries),
            ", "
          )
        )
      end

      local level = #trino_state.failed_queries > 0 and vim.log.levels.WARN or vim.log.levels.INFO
      vim.notify(msg, level, { title = "Trino [" .. trino_state.cluster .. "]" })
    end

    local function execute_trino_query(sql)
      if not sql or sql:match "^%s*$" then
        vim.notify("No SQL to execute", vim.log.levels.WARN, { title = "Trino" })
        return
      end

      if trino_state.current_job then
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
      trino_state.start_time = vim.loop.hrtime()
      show_loading_notification(string.format("Executing queries on %s...", trino_state.cluster))

      run_queries_sequentially(queries, password, otp, auth_user, function()
        show_results()
        open_result_split()
      end)
    end

    -- ============================================================================
    -- Commands
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
          trino_state.cluster = cluster
          vim.notify("Trino cluster set to: " .. cluster, vim.log.levels.INFO, { title = "Trino" })
        else
          vim.notify("Invalid cluster. Use: holdem, war, or faro", vim.log.levels.ERROR, { title = "Trino" })
        end
      else
        vim.ui.select({ "holdem", "war", "faro" }, {
          prompt = "Select Trino cluster:",
          format_item = function(item)
            local marker = item == trino_state.cluster and " (current)" or ""
            return item .. marker
          end,
        }, function(choice)
          if choice then
            trino_state.cluster = choice
            vim.notify("Trino cluster set to: " .. choice, vim.log.levels.INFO, { title = "Trino" })
          end
        end)
      end
    end

    local function trino_cancel()
      if not trino_state.current_job then
        vim.notify("No running query to cancel", vim.log.levels.WARN, { title = "Trino" })
        return
      end

      vim.fn.jobstop(trino_state.current_job)
      trino_state.current_job = nil
      trino_state.start_time = nil
      dismiss_loading_notification()
      vim.notify("Query cancelled", vim.log.levels.INFO, { title = "Trino" })
    end

    local function trino_auth_user(args)
      local user = args.args
      if user and user ~= "" then
        trino_state.cached_auth_user = user
        trino_state.cache_timestamp = os.time()
        vim.notify("Auth user set to: " .. user, vim.log.levels.INFO, { title = "Trino" })
      else
        vim.ui.input({
          prompt = "Auth user (li_authorization_user): ",
          default = trino_state.cached_auth_user or "",
        }, function(input)
          if input and input ~= "" then
            trino_state.cached_auth_user = input
            trino_state.cache_timestamp = os.time()
            vim.notify("Auth user set to: " .. input, vim.log.levels.INFO, { title = "Trino" })
          end
        end)
      end
    end

    -- ============================================================================
    -- Register Commands and Keymaps
    -- ============================================================================

    opts.commands = opts.commands or {}
    opts.commands.TrinoRun = { trino_run, desc = "Run current SQL buffer against Trino" }
    opts.commands.TrinoRunSelection = { trino_run_selection, desc = "Run visual selection against Trino" }
    opts.commands.TrinoCluster = {
      trino_cluster,
      nargs = "?",
      complete = function() return { "holdem", "war", "faro" } end,
      desc = "Set Trino cluster (holdem, war, faro)",
    }
    opts.commands.TrinoCancel = { trino_cancel, desc = "Cancel running Trino query" }
    opts.commands.TrinoAuthUser = {
      trino_auth_user,
      nargs = "?",
      desc = "Set Trino authorization user (li_authorization_user)",
    }
    opts.commands.TrinoClearCache = { clear_credential_cache, desc = "Clear cached Trino credentials" }
    opts.commands.TrinoClear = { clear_result_buffers, desc = "Clear all Trino result buffers" }
    opts.commands.TrinoNext = { trino_next_result, desc = "Navigate to next Trino result buffer" }
    opts.commands.TrinoPrev = { trino_prev_result, desc = "Navigate to previous Trino result buffer" }

    -- Register autocmds for SQL file keymaps
    opts.autocmds = opts.autocmds or {}
    opts.autocmds.trino_sql_keymaps = {
      {
        event = "FileType",
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
          map("n", "<Leader>qc", function() trino_cluster { args = "" } end, "Trino: Change cluster")
          map("n", "<Leader>qu", function() trino_auth_user { args = "" } end, "Trino: Change auth user")
          map("n", "<Leader>qx", trino_cancel, "Trino: Cancel query")
          map("n", "<Leader>qC", clear_result_buffers, "Trino: Clear result buffers")
          map("n", "<Leader>qn", trino_next_result, "Trino: Next result")
          map("n", "<Leader>qp", trino_prev_result, "Trino: Previous result")

          -- Which-key group description
          map("n", "<Leader>q", function() end, "Query (Trino)")
          map("v", "<Leader>q", function() end, "Query (Trino)")
        end,
        desc = "Set up Trino keymaps for SQL files",
      },
    }

    return opts
  end,
}
