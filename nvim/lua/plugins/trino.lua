-- Trino query execution plugin for Neovim
-- Executes SQL queries against LinkedIn's Trino clusters and displays results as CSV
-- Features:
--   - Tree-sitter based SQL parsing for multi-query support
--   - Sequential query execution
--   - Credential caching with TTL
--   - Loading indicator via Snacks.notifier
--   - Results saved as CSV files in ./results/ directory
--   - Uses csvview.nvim for rendering

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
      source_dir = nil, -- directory of the SQL file that started the query
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

    --- Split SQL into individual queries using Tree-sitter
    ---@param sql string The SQL content to parse
    ---@return table queries Array of {index, text}
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

          -- Tree-sitter excludes the semicolon from statement nodes, so add it back
          text = vim.trim(text)
          if not text:match ";$" then text = text .. ";" end

          query_index = query_index + 1
          table.insert(queries, {
            index = query_index,
            text = text,
          })
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
    -- Results Directory Management
    -- ============================================================================

    local function get_results_dir()
      local base_path = trino_state.source_dir
      if not base_path or base_path == "" then base_path = vim.fn.getcwd() end
      return base_path .. "/results"
    end

    local function clear_results_dir()
      local results_dir = get_results_dir()
      local files = vim.fn.glob(results_dir .. "/*.csv", false, true)
      for _, file in ipairs(files) do
        vim.fn.delete(file)
      end
    end

    -- ============================================================================
    -- Query Execution
    -- ============================================================================

    --- Write content to a file
    local function write_file(path, content)
      local f = io.open(path, "w")
      if f then
        f:write(content)
        f:close()
        return true
      end
      return false
    end

    --- Run a single query and write output to a file
    ---@param query_info table {index, text}
    ---@param output_file string Path to write CSV output
    ---@param password string
    ---@param otp string
    ---@param auth_user string The li_authorization_user value
    ---@param on_complete function Callback: function(success, error_msg)
    local function run_single_query(query_info, output_file, password, otp, auth_user, on_complete)
      local query_file = "/tmp/trino_query.sql"
      local temp_output_file = "/tmp/trino_output.csv"
      local stderr_chunks = {}

      if not write_file(query_file, query_info.text) then
        on_complete(false, "Failed to write query file")
        return
      end

      -- Delete any existing temp output file
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
            local has_error = exit_code ~= 0 or stderr_content:match "Query %w+ failed" or stderr_content:match "FAILED"

            if has_error then
              vim.fn.delete(temp_output_file)
              local error_msg = stderr_content ~= "" and stderr_content:sub(1, 200) or "Unknown error"
              on_complete(false, error_msg)
            else
              -- Move temp file to final location only on success
              vim.fn.rename(temp_output_file, output_file)
              on_complete(true, nil)
            end
          end)
        end,
      })

      if job_id <= 0 then
        on_complete(false, "Failed to start job")
        return
      end

      trino_state.current_job = job_id

      -- Send credentials via stdin
      vim.fn.chansend(job_id, password .. "\n")
      vim.fn.chansend(job_id, otp .. "\n")
      vim.fn.chanclose(job_id, "stdin")
    end

    --- Run all queries sequentially
    ---@param queries table Array of query info
    ---@param password string
    ---@param otp string
    ---@param auth_user string The li_authorization_user value
    ---@param on_all_complete function Callback when all queries complete
    local function run_queries_sequentially(queries, password, otp, auth_user, on_all_complete)
      if #queries == 0 then
        on_all_complete()
        return
      end

      local results_dir = get_results_dir()
      vim.fn.mkdir(results_dir, "p")

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
        local output_file = string.format("%s/%d.csv", results_dir, query_info.index)

        update_loading_notification(
          string.format(
            "Query %d/%d on %s...",
            trino_state.completed_count + 1,
            trino_state.total_queries,
            trino_state.cluster
          )
        )

        run_single_query(query_info, output_file, password, otp, auth_user, function(success, error_msg)
          trino_state.completed_count = trino_state.completed_count + 1
          if not success then
            table.insert(trino_state.failed_queries, {
              index = query_info.index,
              error = error_msg,
            })
            vim.fn.delete(output_file) -- Delete failed output
          end

          current_index = current_index + 1
          run_next()
        end)
      end

      run_next()
    end

    --- Show summary notification
    local function show_results()
      dismiss_loading_notification()

      local results_dir = get_results_dir()
      local success_count = trino_state.total_queries - #trino_state.failed_queries

      -- Calculate elapsed time
      local elapsed = ""
      if trino_state.start_time then
        local elapsed_ms = (vim.loop.hrtime() - trino_state.start_time) / 1e6
        if elapsed_ms > 1000 then
          elapsed = string.format(" (%.1fs)", elapsed_ms / 1000)
        else
          elapsed = string.format(" (%dms)", elapsed_ms)
        end
      end

      -- Show summary notification
      local msg
      if trino_state.total_queries == 0 then
        msg = "No data queries to execute"
      elseif #trino_state.failed_queries == 0 then
        msg = string.format(
          "%d/%d queries completed%s\nResults: %s",
          success_count,
          trino_state.total_queries,
          elapsed,
          results_dir
        )
      else
        msg = string.format(
          "%d/%d queries completed%s\nFailed: %s\nResults: %s",
          success_count,
          trino_state.total_queries,
          elapsed,
          table.concat(
            vim.tbl_map(function(q) return string.format("#%d", q.index) end, trino_state.failed_queries),
            ", "
          ),
          results_dir
        )
      end

      local level = #trino_state.failed_queries > 0 and vim.log.levels.WARN or vim.log.levels.INFO
      vim.notify(msg, level, { title = "Trino [" .. trino_state.cluster .. "]" })
    end

    --- Main entry point for executing queries
    local function execute_trino_query(sql)
      if not sql or sql:match "^%s*$" then
        vim.notify("No SQL to execute", vim.log.levels.WARN, { title = "Trino" })
        return
      end

      -- Check if there's already a running job
      if trino_state.current_job then
        vim.notify("Query already running. Cancel it first with :TrinoCancel", vim.log.levels.WARN, { title = "Trino" })
        return
      end

      -- Store the source directory
      trino_state.source_dir = vim.fn.expand "%:p:h"
      if trino_state.source_dir == "" then trino_state.source_dir = vim.fn.getcwd() end

      -- Parse SQL into queries
      local queries = split_queries(sql)

      if #queries == 0 then
        vim.notify("No valid SQL queries found", vim.log.levels.WARN, { title = "Trino" })
        return
      end

      -- Get credentials
      local password, otp, auth_user = get_credentials()
      if not password or not otp or not auth_user then
        vim.notify("Query cancelled - credentials not provided", vim.log.levels.WARN, { title = "Trino" })
        return
      end

      -- Clear previous results
      clear_results_dir()
      vim.fn.mkdir(get_results_dir(), "p")

      -- Record start time
      trino_state.start_time = vim.loop.hrtime()

      -- Show loading notification
      show_loading_notification(string.format("Executing queries on %s...", trino_state.cluster))

      -- Run all queries sequentially
      run_queries_sequentially(queries, password, otp, auth_user, function() show_results() end)
    end

    -- ============================================================================
    -- Commands
    -- ============================================================================

    local function trino_run()
      local ft = vim.bo.filetype
      if ft ~= "sql" then
        vim.notify("TrinoRun only works in .sql files", vim.log.levels.WARN, { title = "Trino" })
        return
      end
      local sql = get_buffer_content()
      execute_trino_query(sql)
    end

    local function trino_run_selection()
      local ft = vim.bo.filetype
      if ft ~= "sql" then
        vim.notify("TrinoRunSelection only works in .sql files", vim.log.levels.WARN, { title = "Trino" })
        return
      end
      local sql = get_visual_selection()
      execute_trino_query(sql)
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
    opts.commands.TrinoRun = {
      trino_run,
      desc = "Run current SQL buffer against Trino",
    }
    opts.commands.TrinoRunSelection = {
      trino_run_selection,
      desc = "Run visual selection against Trino",
    }
    opts.commands.TrinoCluster = {
      trino_cluster,
      nargs = "?",
      complete = function() return { "holdem", "war", "faro" } end,
      desc = "Set Trino cluster (holdem, war, faro)",
    }
    opts.commands.TrinoCancel = {
      trino_cancel,
      desc = "Cancel running Trino query",
    }
    opts.commands.TrinoAuthUser = {
      trino_auth_user,
      nargs = "?",
      desc = "Set Trino authorization user (li_authorization_user)",
    }
    opts.commands.TrinoClearCache = {
      clear_credential_cache,
      desc = "Clear cached Trino credentials",
    }

    -- Register autocmds
    opts.autocmds = opts.autocmds or {}

    opts.autocmds.trino_sql_keymaps = {
      {
        event = "FileType",
        pattern = "sql",
        callback = function(args)
          local bufnr = args.buf

          vim.keymap.set("n", "<Leader>qr", trino_run, {
            buffer = bufnr,
            desc = "Trino: Run query",
          })

          vim.keymap.set("v", "<Leader>qr", function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
            vim.schedule(trino_run_selection)
          end, {
            buffer = bufnr,
            desc = "Trino: Run selection",
          })

          vim.keymap.set("n", "<Leader>qc", function() trino_cluster { args = "" } end, {
            buffer = bufnr,
            desc = "Trino: Change cluster",
          })

          vim.keymap.set("n", "<Leader>qu", function() trino_auth_user { args = "" } end, {
            buffer = bufnr,
            desc = "Trino: Change auth user",
          })

          vim.keymap.set("n", "<Leader>qx", trino_cancel, {
            buffer = bufnr,
            desc = "Trino: Cancel query",
          })

          -- Which-key group description (buffer-local)
          vim.keymap.set("n", "<Leader>q", function() end, {
            buffer = bufnr,
            desc = "Query (Trino)",
          })
          vim.keymap.set("v", "<Leader>q", function() end, {
            buffer = bufnr,
            desc = "Query (Trino)",
          })
        end,
        desc = "Set up Trino keymaps for SQL files",
      },
    }

    return opts
  end,
}
