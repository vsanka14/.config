-- Trino query execution plugin for Neovim
-- Executes SQL queries against LinkedIn's Trino clusters and displays results as CSV
-- Features:
--   - Floating password/OTP prompts
--   - Loading indicator via Snacks.notifier
--   - Results saved as CSV files in ./results/ directory
--   - Uses csvview.nvim for rendering

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = function(_, opts)
    -- ============================================================================
    -- State Management
    -- ============================================================================
    local trino_state = {
      cluster = "holdem", -- default cluster: holdem, war, faro
      current_job = nil, -- current running job
      loading_notif_id = nil, -- loading notification ID for dismissal
      start_time = nil, -- query start time for elapsed calculation
    }

    -- Temp files
    local query_file = "/tmp/trino_query.sql"
    local raw_output_file = "/tmp/trino_raw_output.csv"
    local stderr_file = "/tmp/trino_stderr.log"

    -- ============================================================================
    -- File I/O Helpers
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

    local function read_file(path)
      local f = io.open(path, "r")
      if f then
        local content = f:read "*a"
        f:close()
        return content
      end
      return nil
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
    -- Notification Helpers
    -- ============================================================================

    local function show_loading_notification()
      local ok, Snacks = pcall(require, "snacks")
      if ok and Snacks.notifier then
        trino_state.loading_notif_id = Snacks.notifier.notify(
          "Executing query on " .. trino_state.cluster .. "...",
          vim.log.levels.INFO,
          {
            title = "Trino",
            timeout = false, -- persistent until dismissed
            icon = "󰑮",
          }
        )
      else
        vim.notify(
          "Executing query on " .. trino_state.cluster .. "...",
          vim.log.levels.INFO,
          { title = "Trino" }
        )
      end
    end

    local function dismiss_loading_notification()
      if trino_state.loading_notif_id then
        local ok, Snacks = pcall(require, "snacks")
        if ok and Snacks.notifier then
          Snacks.notifier.hide(trino_state.loading_notif_id)
        end
        trino_state.loading_notif_id = nil
      end
    end

    -- ============================================================================
    -- CSV Parsing
    -- ============================================================================

    --- Check if a line looks like a CSV header (all fields are simple identifiers)
    ---@param line string
    ---@return boolean
    local function is_csv_header(line)
      -- A header line has quoted simple identifiers (letters, numbers, underscores)
      -- Data lines often have complex values like URNs, arrays, etc.
      if not line:match '^"' then
        return false
      end

      -- Split by comma and check each field
      local fields = {}
      for field in line:gmatch '"([^"]*)"' do
        table.insert(fields, field)
      end

      -- Header fields should be simple identifiers (alphanumeric + underscore)
      for _, field in ipairs(fields) do
        if not field:match "^[%w_]+$" then
          return false
        end
      end

      return #fields > 0
    end

    --- Parse CSV output and extract clean data (skip noise lines)
    ---@param content string Raw output from Trino CLI
    ---@return string[] result_sets Array of CSV strings (header + data rows)
    ---@return string[] errors Array of error messages
    local function parse_trino_csv_output(content)
      local lines = vim.split(content, "\n", { trimempty = false })
      local result_sets = {}
      local errors = {}
      local current_csv = {}
      local current_header = nil

      for _, line in ipairs(lines) do
        -- Skip noise lines
        if
          line:match "^%s*$"
          or line:match "^/"
          or line:match "^WARNING:"
          or line:match "^Warning:"
          or line:match "^INFO:"
          or line:match "passwd = fallback"
          or line:match "^%w+ %d+, %d+ %d+:%d+:%d+"
          or line:match "^org%.jline"
          or line:match "^org%.trino"
          or line:match "^Password"
          or line:match "^Yubikey"
          or line:match "getpass"
          or line:match "^SET SESSION"
          or line:match "^USE "
          or line:match "^Authenticat"
        then
          -- Skip noise
        elseif line:match "^Query %w+ failed" or line:match "^Error" then
          table.insert(errors, line)
        elseif line == '"result"' then
          -- Skip SET SESSION result header
          current_header = "__SKIP__"
        elseif current_header == "__SKIP__" then
          -- Skip data row after SET SESSION result header
          if line == '"true"' or line == '"false"' then
            current_header = nil
          end
        elseif line:match '^"' then
          -- This looks like CSV data
          if is_csv_header(line) then
            -- This is a new header - save previous result set if any
            if #current_csv > 1 then
              table.insert(result_sets, table.concat(current_csv, "\n"))
            end
            -- Start new result set
            current_csv = { line }
            current_header = line
          elseif current_header and current_header ~= "__SKIP__" then
            -- Data row for current result set
            table.insert(current_csv, line)
          end
        elseif #errors > 0 then
          -- Continuation of error message
          table.insert(errors, line)
        end
      end

      -- Don't forget last result set
      if #current_csv > 1 then
        table.insert(result_sets, table.concat(current_csv, "\n"))
      end

      return result_sets, errors
    end

    --- Count rows in CSV (excluding header)
    ---@param csv_content string
    ---@return number
    local function count_csv_rows(csv_content)
      local count = 0
      for _ in csv_content:gmatch "[^\n]+" do
        count = count + 1
      end
      return math.max(0, count - 1) -- Subtract header
    end

    -- ============================================================================
    -- Results Saving
    -- ============================================================================

    --- Get results directory path (./results/ relative to current buffer's directory)
    ---@return string
    local function get_results_dir()
      local buf_path = vim.fn.expand "%:p:h"
      if buf_path == "" then
        buf_path = vim.fn.getcwd()
      end
      return buf_path .. "/results"
    end

    --- Clear all existing CSV files in results directory
    local function clear_results_dir()
      local results_dir = get_results_dir()
      local files = vim.fn.glob(results_dir .. "/*.csv", false, true)
      for _, file in ipairs(files) do
        vim.fn.delete(file)
      end
    end

    --- Generate a unique filename for results
    ---@param query_index number
    ---@param total_queries number
    ---@return string
    local function generate_result_filename(query_index, total_queries)
      if total_queries > 1 then
        return string.format("result_%d.csv", query_index)
      else
        return "result.csv"
      end
    end

    --- Save CSV result to file and open it
    ---@param csv_content string
    ---@param query_index number
    ---@param total_queries number
    ---@return string|nil filepath Path to saved file, or nil on error
    local function save_and_open_result(csv_content, query_index, total_queries)
      local results_dir = get_results_dir()

      -- Create results directory if it doesn't exist
      vim.fn.mkdir(results_dir, "p")

      -- Generate filename and full path
      local filename = generate_result_filename(query_index, total_queries)
      local filepath = results_dir .. "/" .. filename

      -- Write CSV content
      if not write_file(filepath, csv_content) then
        vim.notify("Failed to write results to " .. filepath, vim.log.levels.ERROR, { title = "Trino" })
        return nil
      end

      -- Open the file
      vim.cmd("edit " .. vim.fn.fnameescape(filepath))

      return filepath
    end

    -- ============================================================================
    -- Results Display
    -- ============================================================================

    --- Open all results
    local function open_results()
      local content = read_file(raw_output_file)
      local stderr_content = read_file(stderr_file)

      -- Check stderr for actual errors
      if stderr_content then
        local has_error = stderr_content:match "Query %w+ failed"
          or stderr_content:match "^Error"
          or stderr_content:match "FAILED"
        if has_error then
          vim.notify("Query error:\n" .. stderr_content, vim.log.levels.ERROR, { title = "Trino" })
        end
      end

      if not content or content == "" then
        if stderr_content and stderr_content ~= "" then
          vim.notify(
            "No data returned. Check stderr:\n" .. stderr_content:sub(1, 500),
            vim.log.levels.WARN,
            { title = "Trino" }
          )
        else
          vim.notify("No results returned from Trino", vim.log.levels.WARN, { title = "Trino" })
        end
        return
      end

      -- Parse CSV output
      local result_sets, errors = parse_trino_csv_output(content)

      -- Check for errors
      if #errors > 0 then
        vim.notify("Query error:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR, { title = "Trino" })
      end

      -- Check if we have any results
      if #result_sets == 0 then
        if #errors == 0 then
          vim.notify("Query completed but returned no data", vim.log.levels.INFO, { title = "Trino" })
        end
        return
      end

      -- Save and open each result set
      local total_rows = 0
      local saved_files = {}
      for i, csv_content in ipairs(result_sets) do
        local row_count = count_csv_rows(csv_content)
        total_rows = total_rows + row_count
        local filepath = save_and_open_result(csv_content, i, #result_sets)
        if filepath then
          table.insert(saved_files, filepath)
        end
      end

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

      -- Show completion notification
      local msg = string.format("Query complete: %d rows%s", total_rows, elapsed)
      if #saved_files > 0 then
        msg = msg .. "\nSaved to: " .. saved_files[1]
        if #saved_files > 1 then
          msg = msg .. string.format(" (+%d more)", #saved_files - 1)
        end
      end
      vim.notify(msg, vim.log.levels.INFO, { title = "Trino [" .. trino_state.cluster .. "]" })
    end

    -- ============================================================================
    -- Query Execution
    -- ============================================================================

    local function execute_trino_query(sql)
      if not sql or sql:match "^%s*$" then
        vim.notify("No SQL to execute", vim.log.levels.WARN, { title = "Trino" })
        return
      end

      -- Write query to temp file
      if not write_file(query_file, sql) then
        vim.notify("Failed to write query file", vim.log.levels.ERROR, { title = "Trino" })
        return
      end

      -- Clear previous results
      write_file(raw_output_file, "")
      write_file(stderr_file, "")
      clear_results_dir()

      -- Step 1: Prompt for password
      vim.ui.input({
        prompt = "Trino [" .. trino_state.cluster .. "] - Password: ",
      }, function(password)
        if not password or password == "" then
          vim.notify("Query cancelled - no password provided", vim.log.levels.WARN, { title = "Trino" })
          return
        end

        -- Step 2: Prompt for OTP
        vim.ui.input({
          prompt = "Trino [" .. trino_state.cluster .. "] - OTP: ",
        }, function(otp)
          if not otp or otp == "" then
            vim.notify("Query cancelled - no OTP provided", vim.log.levels.WARN, { title = "Trino" })
            return
          end

          -- Record start time
          trino_state.start_time = vim.loop.hrtime()

          -- Show loading notification
          show_loading_notification()

          -- Build command (use CSV_HEADER output format)
          local cmd = {
            "sh",
            "-c",
            string.format(
              "trino query -c %s -f %s --output-format CSV_HEADER > %s 2>%s",
              trino_state.cluster,
              query_file,
              raw_output_file,
              stderr_file
            ),
          }

          -- Start job
          local job_id = vim.fn.jobstart(cmd, {
            stdin = "pipe",
            on_exit = function(_, exit_code, _)
              vim.schedule(function()
                -- Dismiss loading notification first
                dismiss_loading_notification()

                trino_state.current_job = nil

                -- Open results
                open_results()
              end)
            end,
          })

          if job_id <= 0 then
            dismiss_loading_notification()
            vim.notify("Failed to start Trino query", vim.log.levels.ERROR, { title = "Trino" })
            return
          end

          trino_state.current_job = job_id

          -- Send password and OTP to stdin (each on separate line)
          vim.fn.chansend(job_id, password .. "\n")
          vim.fn.chansend(job_id, otp .. "\n")
          vim.fn.chanclose(job_id, "stdin")
        end)
      end)
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
        -- Show picker
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
      complete = function()
        return { "holdem", "war", "faro" }
      end,
      desc = "Set Trino cluster (holdem, war, faro)",
    }

    -- Register autocmds for SQL filetype keymaps
    opts.autocmds = opts.autocmds or {}
    opts.autocmds.trino_sql_keymaps = {
      {
        event = "FileType",
        pattern = "sql",
        callback = function(args)
          local bufnr = args.buf

          -- <Leader>qr - Run buffer (normal mode)
          vim.keymap.set("n", "<Leader>qr", trino_run, {
            buffer = bufnr,
            desc = "Trino: Run query",
          })

          -- <Leader>qr - Run selection (visual mode)
          vim.keymap.set("v", "<Leader>qr", function()
            -- Exit visual mode first to set '< and '> marks
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
            vim.schedule(trino_run_selection)
          end, {
            buffer = bufnr,
            desc = "Trino: Run selection",
          })

          -- <Leader>qc - Change cluster
          vim.keymap.set("n", "<Leader>qc", function()
            trino_cluster { args = "" }
          end, {
            buffer = bufnr,
            desc = "Trino: Change cluster",
          })
        end,
        desc = "Set up Trino keymaps for SQL files",
      },
    }

    -- Add which-key group description
    opts.mappings = opts.mappings or {}
    opts.mappings.n = opts.mappings.n or {}
    opts.mappings.n["<Leader>q"] = { desc = "Query (Trino)" }
    opts.mappings.v = opts.mappings.v or {}
    opts.mappings.v["<Leader>q"] = { desc = "Query (Trino)" }

    return opts
  end,
}
