-- trino.lua — Run Trino SQL queries from Neovim
--
-- Dependencies: `trino` CLI (LinkedIn).
--
-- Setup:
--   require("trino").setup({
--     cluster = "holdem",              -- default cluster (holdem | war | faro)
--     headless_user = "myuser",        -- li_authorization_user (prompted if nil)
--     split_height_pct = 50,           -- result split height as % of editor
--   })
--
-- Commands:
--   :TrinoRun              Run whole buffer, or visual selection
--   :TrinoCluster [name]   Switch cluster. Interactive picker if no arg.
--   :TrinoCancel           Cancel the running query for the current SQL file
--   :TrinoHeadlessUser [u] Set li_authorization_user. Prompt if no arg.
--   :TrinoNext / TrinoPrev Cycle through result buffers for the current SQL file
--
-- Lifecycle hooks (wired from autocmds.lua):
--   M.on_buf_enter(buf), M.on_win_closed(win), M.on_source_wiped(buf)
--
-- Everything is scoped per source SQL buffer: each file has its own running
-- job, its own result buffers, and its own cancel state. Multiple files can
-- run queries concurrently. Switching to a different SQL file swaps the
-- result split's contents (or closes it if that file has no stored results).

local M = {}

local state = {
	cluster = "holdem",
	headless_user = nil,
	results_by_source = {},
	result_win = nil,
	window_source = nil,
	split_height_pct = 50,
}

-- ============================================================================
-- SQL Extraction Helpers
-- ============================================================================

local function get_visual_selection()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
	return table.concat(lines, "\n")
end

local function get_buffer_content(buf)
	local lines = vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false)
	return table.concat(lines, "\n")
end

-- ============================================================================
-- Result Buffer Management (per-source)
-- ============================================================================

local function is_result_win_valid()
	return state.result_win and vim.api.nvim_win_is_valid(state.result_win)
end

local function entry_buffers(src_buf)
	local entry = state.results_by_source[src_buf]
	return entry and entry.buffers or {}
end

local function close_result_window()
	if is_result_win_valid() then
		vim.api.nvim_win_close(state.result_win, true)
	end
	state.result_win = nil
	state.window_source = nil
end

local function delete_results_for(src_buf)
	local entry = state.results_by_source[src_buf]
	if not entry then
		return
	end
	if entry.job then
		entry.job.cancelled = true
		pcall(vim.fn.jobstop, entry.job.id)
	end
	for _, e in ipairs(entry.buffers) do
		if vim.api.nvim_buf_is_valid(e.buf) then
			pcall(vim.api.nvim_buf_delete, e.buf, { force = true })
		end
	end
	state.results_by_source[src_buf] = nil
	if state.window_source == src_buf then
		close_result_window()
	end
end

local function get_result_winbar()
	if not is_result_win_valid() or not state.window_source then
		return ""
	end
	local buffers = entry_buffers(state.window_source)
	if #buffers == 0 then
		return ""
	end
	local current_buf = vim.api.nvim_win_get_buf(state.result_win)
	local parts = {}
	for _, e in ipairs(buffers) do
		local hl = (e.buf == current_buf) and "%#TabLineSel#" or "%#TabLine#"
		table.insert(parts, string.format("%s %d %%*", hl, e.index))
	end
	return table.concat(parts, "%#TabLineFill#|")
end

local function refresh_result_winbar()
	if is_result_win_valid() then
		vim.wo[state.result_win].winbar = get_result_winbar()
	end
end

local function create_result_buffer(src_buf, index, lines)
	local buf = vim.api.nvim_create_buf(false, true)
	if buf == 0 then
		vim.notify("Failed to create result buffer", vim.log.levels.ERROR, { title = "Trino" })
		return
	end

	local src_name = vim.api.nvim_buf_get_name(src_buf)
	local short = src_name ~= "" and vim.fn.fnamemodify(src_name, ":t") or ("buf" .. src_buf)
	pcall(vim.api.nvim_buf_set_name, buf, string.format("trino://%s/%d", short, index))
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	local entry = state.results_by_source[src_buf]
	if not entry then
		entry = { buffers = {} }
		state.results_by_source[src_buf] = entry
	end
	table.insert(entry.buffers, { buf = buf, index = index })
end

-- Show the result split for src_buf, or close it if src_buf has no results.
local function show_results_for(src_buf)
	local buffers = entry_buffers(src_buf)
	if #buffers == 0 then
		close_result_window()
		return
	end

	local first = buffers[1].buf
	if not vim.api.nvim_buf_is_valid(first) then
		return
	end

	if is_result_win_valid() then
		if state.window_source ~= src_buf then
			vim.api.nvim_win_set_buf(state.result_win, first)
			state.window_source = src_buf
		end
		refresh_result_winbar()
		return
	end

	local origin_win = vim.api.nvim_get_current_win()
	local split_height = math.floor(vim.o.lines * state.split_height_pct / 100)

	vim.cmd(string.format("botright %dsplit", split_height))
	state.result_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(state.result_win, first)
	state.window_source = src_buf

	refresh_result_winbar()

	if origin_win and vim.api.nvim_win_is_valid(origin_win) then
		vim.api.nvim_set_current_win(origin_win)
	end
end

local function get_current_result_index()
	if not is_result_win_valid() or not state.window_source then
		return nil
	end
	local current_buf = vim.api.nvim_win_get_buf(state.result_win)
	for i, e in ipairs(entry_buffers(state.window_source)) do
		if e.buf == current_buf then
			return i
		end
	end
	return nil
end

local function switch_to_result(index)
	if not is_result_win_valid() or not state.window_source then
		return
	end
	local buffers = entry_buffers(state.window_source)
	local e = buffers[index]
	if e and vim.api.nvim_buf_is_valid(e.buf) then
		vim.api.nvim_win_set_buf(state.result_win, e.buf)
		refresh_result_winbar()
	end
end

local function trino_next_result()
	if not state.window_source or #entry_buffers(state.window_source) == 0 then
		vim.notify("No result buffers available", vim.log.levels.WARN, { title = "Trino" })
		return
	end
	if not is_result_win_valid() then
		show_results_for(state.window_source)
		return
	end
	local total = #entry_buffers(state.window_source)
	local current_idx = get_current_result_index() or 0
	switch_to_result((current_idx % total) + 1)
end

local function trino_prev_result()
	if not state.window_source or #entry_buffers(state.window_source) == 0 then
		vim.notify("No result buffers available", vim.log.levels.WARN, { title = "Trino" })
		return
	end
	if not is_result_win_valid() then
		show_results_for(state.window_source)
		return
	end
	local total = #entry_buffers(state.window_source)
	local current_idx = get_current_result_index() or 1
	switch_to_result(((current_idx - 2) % total) + 1)
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
	if not f then
		return nil
	end
	local lines = {}
	for line in f:lines() do
		table.insert(lines, line)
	end
	f:close()
	return lines
end

-- Trino's --output table emits a single empty line between consecutive query
-- results. Slice on blank lines so each query gets its own buffer.
local function split_output_chunks(lines)
	local chunks = {}
	local current = {}
	for _, line in ipairs(lines) do
		if line == "" then
			if #current > 0 then
				table.insert(chunks, current)
				current = {}
			end
		else
			table.insert(current, line)
		end
	end
	if #current > 0 then
		table.insert(chunks, current)
	end
	return chunks
end

local function format_elapsed_ms(ms)
	if ms > 1000 then
		return string.format(" (%.1fs)", ms / 1000)
	end
	return string.format(" (%dms)", ms)
end

local function show_error_for(src_buf, message)
	delete_results_for(src_buf)
	create_result_buffer(src_buf, 1, vim.split(message, "\n"))
	-- Only swap the split if the user is currently focused on this source.
	-- Otherwise the buffers stay in the map and will appear when they switch back.
	if vim.api.nvim_get_current_buf() == src_buf then
		show_results_for(src_buf)
	end
end

local function show_results_for_lines(src_buf, out_lines)
	local chunks = split_output_chunks(out_lines)
	if #chunks == 0 then
		chunks = { { "Query returned no results." } }
	end

	delete_results_for(src_buf)
	for i, chunk in ipairs(chunks) do
		create_result_buffer(src_buf, i, chunk)
	end
	if vim.api.nvim_get_current_buf() == src_buf then
		show_results_for(src_buf)
	end
end

local function run_trino(src_buf, sql, auth_user)
	local start_time = vim.loop.hrtime()
	local base = vim.fn.tempname()
	local query_file = base .. ".sql"
	local out_file = base .. "_out.txt"
	local log_file = base .. "_log.txt"

	-- Trino CLI errors on a trailing `;` when the file contains a single
	-- statement (it's expecting EOF). Inner `;` separators are fine, so we
	-- only strip the very last one.
	local sql_to_run = (sql:gsub(";%s*$", ""))

	if not write_file(query_file, sql_to_run) then
		vim.notify("Failed to write query file", vim.log.levels.ERROR, { title = "Trino" })
		return
	end

	local cluster = state.cluster
	local trino_cmd = string.format(
		"trino query -c %s -f %s -u %s --sso --interactive --browser --output table > %s 2> %s",
		cluster,
		query_file,
		auth_user,
		out_file,
		log_file
	)

	vim.notify(string.format("Executing on %s...", cluster), vim.log.levels.INFO, { title = "Trino" })

	local job = { id = nil, cancelled = false }
	local entry = state.results_by_source[src_buf]
	if not entry then
		entry = { buffers = {} }
		state.results_by_source[src_buf] = entry
	end
	entry.job = job

	local job_id = vim.fn.jobstart({ "sh", "-c", trino_cmd }, {
		on_exit = function(_, exit_code)
			vim.schedule(function()
				local elapsed = format_elapsed_ms((vim.loop.hrtime() - start_time) / 1e6)
				local title = "Trino [" .. cluster .. "]"

				-- Source may have been wiped mid-query, or replaced by a newer
				-- run. Only clear the job pointer if it's still ours.
				local cur = state.results_by_source[src_buf]
				if cur and cur.job == job then
					cur.job = nil
				end

				if not vim.api.nvim_buf_is_valid(src_buf) or not cur then
					vim.fn.delete(query_file)
					vim.fn.delete(out_file)
					vim.fn.delete(log_file)
					return
				end

				vim.fn.delete(query_file)

				if job.cancelled then
					vim.fn.delete(out_file)
					vim.fn.delete(log_file)
					show_error_for(src_buf, "Cancelled.")
					vim.notify("Query cancelled" .. elapsed, vim.log.levels.WARN, { title = title })
					return
				end

				if exit_code ~= 0 then
					vim.fn.delete(out_file)
					local stderr = read_file_lines(log_file) or {}
					vim.fn.delete(log_file)
					local body = #stderr > 0 and table.concat(stderr, "\n") or ("Exit code " .. exit_code)
					show_error_for(src_buf, body)
					vim.notify("Query failed" .. elapsed, vim.log.levels.ERROR, { title = title })
					return
				end

				vim.fn.delete(log_file)
				local out_lines = read_file_lines(out_file) or {}
				vim.fn.delete(out_file)
				show_results_for_lines(src_buf, out_lines)
				local n = #entry_buffers(src_buf)
				vim.notify(
					string.format("%d result%s%s", n, n == 1 and "" or "s", elapsed),
					vim.log.levels.INFO,
					{ title = title }
				)
			end)
		end,
	})

	if job_id <= 0 then
		entry.job = nil
		vim.notify("Failed to start trino job", vim.log.levels.ERROR, { title = "Trino" })
		return
	end

	job.id = job_id
end

local function execute_trino_query(src_buf, sql)
	if not sql or sql:match("^%s*$") then
		vim.notify("No SQL to execute", vim.log.levels.WARN, { title = "Trino" })
		return
	end

	local entry = state.results_by_source[src_buf]
	if entry and entry.job then
		vim.notify(
			"Query already running for this file. Cancel it first with :TrinoCancel",
			vim.log.levels.WARN,
			{ title = "Trino" }
		)
		return
	end

	local function proceed(user)
		run_trino(src_buf, sql, user)
	end

	if not state.headless_user then
		vim.ui.input({ prompt = "Auth user (li_authorization_user): " }, function(input)
			if not input or input == "" then
				vim.notify("Auth user is required", vim.log.levels.WARN, { title = "Trino" })
				return
			end
			state.headless_user = input
			proceed(input)
		end)
	else
		proceed(state.headless_user)
	end
end

-- ============================================================================
-- Command Handlers
-- ============================================================================

local function trino_run(args)
	if vim.bo.filetype ~= "sql" then
		vim.notify("TrinoRun only works in .sql files", vim.log.levels.WARN, { title = "Trino" })
		return
	end
	local src_buf = vim.api.nvim_get_current_buf()
	if args.range > 0 then
		execute_trino_query(src_buf, get_visual_selection())
	else
		execute_trino_query(src_buf, get_buffer_content(src_buf))
	end
end

local VALID_CLUSTERS = { holdem = true, war = true, faro = true }

local function trino_cluster(args)
	local cluster = args.args
	if cluster and cluster ~= "" then
		if VALID_CLUSTERS[cluster] then
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
	if vim.bo.filetype ~= "sql" then
		vim.notify("TrinoCancel only works in .sql files", vim.log.levels.WARN, { title = "Trino" })
		return
	end
	local src_buf = vim.api.nvim_get_current_buf()
	local entry = state.results_by_source[src_buf]
	if not entry or not entry.job then
		vim.notify("No running query for this file", vim.log.levels.WARN, { title = "Trino" })
		return
	end
	entry.job.cancelled = true
	pcall(vim.fn.jobstop, entry.job.id)
	entry.job = nil
end

local function trino_auth_user(args)
	local user = args.args
	if user and user ~= "" then
		state.headless_user = user
		vim.notify("Auth user set to: " .. user, vim.log.levels.INFO, { title = "Trino" })
	else
		vim.ui.input({
			prompt = "Auth user (li_authorization_user): ",
			default = state.headless_user or "",
		}, function(input)
			if input and input ~= "" then
				state.headless_user = input
				vim.notify("Auth user set to: " .. input, vim.log.levels.INFO, { title = "Trino" })
			end
		end)
	end
end

-- ============================================================================
-- Lifecycle hooks (wired from autocmds.lua)
-- ============================================================================

function M.on_buf_enter(buf)
	local entry = state.results_by_source[buf]
	if entry and not entry.dismissed then
		show_results_for(buf)
	else
		close_result_window()
	end
end

function M.on_win_closed(win)
	if win ~= state.result_win then
		return
	end
	local entry = state.window_source and state.results_by_source[state.window_source]
	if entry then
		entry.dismissed = true
	end
	state.result_win = nil
	state.window_source = nil
end

function M.on_source_wiped(buf)
	if state.results_by_source[buf] then
		delete_results_for(buf)
	end
end

-- ============================================================================
-- Setup
-- ============================================================================

function M.setup(opts)
	opts = opts or {}
	if opts.cluster ~= nil then
		state.cluster = opts.cluster
	end
	if opts.headless_user ~= nil then
		state.headless_user = opts.headless_user
	end
	if opts.split_height_pct ~= nil then
		state.split_height_pct = opts.split_height_pct
	end

	vim.api.nvim_create_user_command(
		"TrinoRun",
		trino_run,
		{ range = true, desc = "Run SQL against Trino (buffer or selection)" }
	)
	vim.api.nvim_create_user_command("TrinoCluster", trino_cluster, {
		nargs = "?",
		complete = function()
			return { "holdem", "war", "faro" }
		end,
		desc = "Set Trino cluster",
	})
	vim.api.nvim_create_user_command(
		"TrinoCancel",
		trino_cancel,
		{ desc = "Cancel running Trino query for current file" }
	)
	vim.api.nvim_create_user_command("TrinoHeadlessUser", trino_auth_user, {
		nargs = "?",
		desc = "Set Trino authorization user",
	})
	vim.api.nvim_create_user_command("TrinoNext", trino_next_result, { desc = "Next Trino result buffer" })
	vim.api.nvim_create_user_command("TrinoPrev", trino_prev_result, { desc = "Previous Trino result buffer" })
end

return M
