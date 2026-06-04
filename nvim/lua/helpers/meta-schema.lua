-- meta-schema.lua — async client that fetches a dataset's schema via LinkedIn's
-- `meta` CLI and caches it for the Neovim session.
--
-- Shells out to:
--   meta dataset latest-schema -p <platform> -n <dataset> [-o <origin>] --quiet
-- which returns JSON from the metadata service (no live query, no Trino compute,
-- no SSO browser popup). We read the ORC schema string out of `platformSchema`
-- and parse it into { name, type } columns (camelCase preserved, fully nested).
--
-- Everything is async (vim.fn.jobstart) so the editor never blocks. Results are
-- cached per `platform:dataset`; failures are cached with a short TTL to avoid
-- retry storms.

local sqld = require("helpers.sql-datasets")

local M = {}

local config = {
	platform = "gridTable", -- meta data-platform the datasets live on
	origin = nil, -- optional data origin (corp|dev|ei|prod); nil = let meta decide
	timeout_ms = 30000, -- terminate a schema job that runs longer than this
	max_jobs = 2, -- global cap on concurrent schema jobs
	failure_ttl_ms = 30000, -- how long to remember a failure before retrying
	list_count = 100, -- max dataset names to request per `meta dataset list`
	list_min_prefix = 2, -- shortest prefix we'll list datasets for
	list_max_jobs = 1, -- cap on concurrent `meta dataset list` jobs
}

-- cache[key] = {
--   state = "pending" | "ready" | "failed",
--   columns = { { name = ..., type = ... }, ... },
--   ts = <ms>, job_id = <int|nil>, callbacks = { fn, ... }, dataset = <string>,
-- }
local cache = {}
local active_jobs = 0
local pending_queue = {} -- datasets waiting for a free job slot

local run_job -- forward declaration (mutually recursive with process_queue)

local function now_ms()
	return vim.loop.now()
end

local function key_for(dataset)
	return config.platform .. ":" .. (config.origin or "") .. ":" .. dataset
end

-- Pull the ORC schema string (a Hive `struct<...>`) out of meta's JSON and
-- parse it into top-level columns. Returns a { name, type } list (possibly
-- empty) or nil if the payload has no recognizable schema.
local function columns_from_json(text)
	local start = text:find("{", 1, true)
	if not start then
		return nil
	end
	local ok, decoded = pcall(vim.json.decode, text:sub(start))
	if not ok or type(decoded) ~= "table" then
		return nil
	end

	local orc
	local ps = decoded.platformSchema
	if type(ps) == "table" then
		for _, v in pairs(ps) do
			if type(v) == "table" and type(v.orcSchema) == "string" then
				orc = v.orcSchema
				break
			end
		end
	end
	if type(orc) ~= "string" then
		return nil
	end

	return sqld.struct_fields(orc) or {}
end

local function fire_callbacks(entry)
	local cbs = entry.callbacks or {}
	entry.callbacks = {}
	for _, cb in ipairs(cbs) do
		pcall(cb, entry)
	end
end

local function process_queue()
	while active_jobs < config.max_jobs and #pending_queue > 0 do
		local ds = table.remove(pending_queue, 1)
		local entry = cache[key_for(ds)]
		if entry and entry.state == "pending" and not entry.job_id then
			run_job(ds)
		end
	end
end

function run_job(dataset)
	local k = key_for(dataset)
	local entry = cache[k]
	if not entry then
		return
	end

	active_jobs = active_jobs + 1
	local stdout_lines, stderr_lines = {}, {}
	local timer

	local function collect(target)
		return function(_, data)
			if data then
				for _, l in ipairs(data) do
					target[#target + 1] = l
				end
			end
		end
	end

	-- argv form (no shell) — `dataset` is validated by the caller and never
	-- interpolated into a shell string, so there's no injection surface.
	local cmd = {
		"meta",
		"dataset",
		"latest-schema",
		"-p",
		config.platform,
		"-n",
		dataset,
		"--quiet",
	}
	if config.origin and config.origin ~= "" then
		cmd[#cmd + 1] = "-o"
		cmd[#cmd + 1] = config.origin
	end

	local job_id = vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = collect(stdout_lines),
		on_stderr = collect(stderr_lines),
		on_exit = function(_, code)
			vim.schedule(function()
				if timer then
					timer:stop()
					timer:close()
					timer = nil
				end
				active_jobs = math.max(0, active_jobs - 1)

				local e = cache[k]
				if e then
					e.job_id = nil
					e.ts = now_ms()
					local cols = (code == 0) and columns_from_json(table.concat(stdout_lines, "\n")) or nil
					if cols then
						e.state = "ready"
						e.columns = cols
					else
						e.state = "failed"
						e.columns = {}
						e.err = table.concat(stderr_lines, "\n")
						vim.notify_once(
							"meta schema fetch failed for "
								.. dataset
								.. " (platform="
								.. config.platform
								.. "; check name/platform)",
							vim.log.levels.WARN,
							{ title = "Meta" }
						)
					end
					fire_callbacks(e)
				end
				process_queue()
			end)
		end,
	})

	if job_id <= 0 then
		active_jobs = math.max(0, active_jobs - 1)
		entry.state = "failed"
		entry.ts = now_ms()
		fire_callbacks(entry)
		return
	end

	entry.job_id = job_id
	timer = vim.loop.new_timer()
	timer:start(config.timeout_ms, 0, function()
		vim.schedule(function()
			pcall(vim.fn.jobstop, job_id)
		end)
	end)
end

-- ── Dataset-name listing (`meta dataset list`) ──────────────────────────────
-- Powers FROM/JOIN dataset *name* completion. meta does a `name:(prefix*)`
-- match, so a prefix's results are a superset of any longer prefix's results —
-- we reuse a cached (untruncated) shorter prefix instead of re-shelling out.
local list_cache = {} -- [prefix] = { state, names = {}, ts, job_id, callbacks = {}, truncated }
local list_active = 0
local list_queue = {}
local run_list_job -- forward declaration (mutually recursive with process_list_queue)

local function fire_list_callbacks(entry)
	local cbs = entry.callbacks or {}
	entry.callbacks = {}
	for _, cb in ipairs(cbs) do
		pcall(cb, entry)
	end
end

-- Parse meta's stdout: one dataset name per line, with an optional trailing
-- "And N more..." marker that we fold into a `truncated` flag.
local function names_from_lines(lines)
	local names, truncated = {}, false
	for _, l in ipairs(lines) do
		local s = l:gsub("^%s+", ""):gsub("%s+$", "")
		if s ~= "" then
			if s:match("^And%s+%d+%s+more") then
				truncated = true
			else
				names[#names + 1] = s
			end
		end
	end
	return names, truncated
end

local function process_list_queue()
	while list_active < config.list_max_jobs and #list_queue > 0 do
		local prefix = table.remove(list_queue, 1)
		local entry = list_cache[prefix]
		if entry and entry.state == "pending" and not entry.job_id then
			run_list_job(prefix)
		end
	end
end

function run_list_job(prefix)
	local entry = list_cache[prefix]
	if not entry then
		return
	end

	list_active = list_active + 1
	local stdout_lines, stderr_lines = {}, {}
	local timer

	local function collect(target)
		return function(_, data)
			if data then
				for _, l in ipairs(data) do
					target[#target + 1] = l
				end
			end
		end
	end

	-- argv form (no shell); `prefix` is validated `[%w_%.]+` by the caller.
	local cmd = {
		"meta",
		"dataset",
		"list",
		"-p",
		config.platform,
		"-n",
		prefix,
		"--count",
		tostring(config.list_count),
		"--quiet",
	}
	if config.origin and config.origin ~= "" then
		cmd[#cmd + 1] = "-o"
		cmd[#cmd + 1] = config.origin
	end

	local job_id = vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = collect(stdout_lines),
		on_stderr = collect(stderr_lines),
		on_exit = function(_, code)
			vim.schedule(function()
				if timer then
					timer:stop()
					timer:close()
					timer = nil
				end
				list_active = math.max(0, list_active - 1)

				local e = list_cache[prefix]
				if e then
					e.job_id = nil
					e.ts = now_ms()
					if code == 0 then
						local names, truncated = names_from_lines(stdout_lines)
						e.state = "ready"
						e.names = names
						e.truncated = truncated
					else
						e.state = "failed"
						e.names = {}
						e.err = table.concat(stderr_lines, "\n")
					end
					fire_list_callbacks(e)
				end
				process_list_queue()
			end)
		end,
	})

	if job_id <= 0 then
		list_active = math.max(0, list_active - 1)
		entry.state = "failed"
		entry.ts = now_ms()
		fire_list_callbacks(entry)
		return
	end

	entry.job_id = job_id
	timer = vim.loop.new_timer()
	timer:start(config.timeout_ms, 0, function()
		vim.schedule(function()
			pcall(vim.fn.jobstop, job_id)
		end)
	end)
end

local function valid_prefix(prefix)
	return type(prefix) == "string" and #prefix >= config.list_min_prefix and prefix:match("^[%w_%.]+$") ~= nil
end

-- Longest cached, ready, *untruncated* prefix of `prefix` (exact match wins).
-- Truncated entries are skipped because a longer prefix could surface names
-- that fell past the result cap.
local function best_list_entry(prefix)
	local exact = list_cache[prefix]
	if exact and exact.state == "ready" then
		return exact
	end
	local best, best_len
	for p, ent in pairs(list_cache) do
		if
			ent.state == "ready"
			and not ent.truncated
			and #p >= config.list_min_prefix
			and p == prefix:sub(1, #p)
		then
			if not best_len or #p > best_len then
				best, best_len = ent, #p
			end
		end
	end
	return best
end

-- Public: best available cached name list for `prefix` (never starts a fetch).
function M.list_get(prefix)
	if not valid_prefix(prefix) then
		return { state = "absent", names = {} }
	end
	local e = best_list_entry(prefix)
	if e then
		return e
	end
	local exact = list_cache[prefix]
	if exact and exact.state == "pending" then
		return exact
	end
	return { state = "absent", names = {} }
end

-- Public: ensure dataset names for `prefix` are fetched (or reused). `cb` is
-- invoked with the cache entry once names are ready or the fetch fails.
function M.list(prefix, cb)
	if not valid_prefix(prefix) then
		if cb then
			cb({ state = "absent", names = {} })
		end
		return
	end

	-- Reuse a ready (untruncated) ancestor or exact entry — no new process.
	local ready = best_list_entry(prefix)
	if ready then
		if cb then
			cb(ready)
		end
		return
	end

	local entry = list_cache[prefix]
	if entry then
		if entry.state == "pending" then
			if cb then
				entry.callbacks[#entry.callbacks + 1] = cb
			end
			return
		elseif entry.state == "failed" then
			if now_ms() - (entry.ts or 0) < config.failure_ttl_ms then
				if cb then
					cb(entry)
				end
				return
			end
		end
	end

	list_cache[prefix] = { state = "pending", names = {}, callbacks = cb and { cb } or {} }
	if list_active < config.list_max_jobs then
		run_list_job(prefix)
	else
		list_queue[#list_queue + 1] = prefix
	end
end

-- Public: current cache entry for a dataset (never starts a fetch).
-- Returns a table with at least `state` ("absent"|"pending"|"ready"|"failed")
-- and `columns`.
function M.get(dataset)
	return cache[key_for(dataset)] or { state = "absent", columns = {} }
end

-- Public: ensure a fetch is underway (or done) for `dataset`. If `cb` is given
-- it is invoked with the cache entry once columns are ready or the fetch fails.
-- Already-ready datasets invoke `cb` synchronously.
function M.fetch(dataset, cb)
	if type(dataset) ~= "string" or not dataset:match("^[%w_]+%.[%w_]+") then
		return
	end
	local k = key_for(dataset)
	local entry = cache[k]

	if entry then
		if entry.state == "ready" then
			if cb then
				cb(entry)
			end
			return
		elseif entry.state == "pending" then
			if cb then
				entry.callbacks[#entry.callbacks + 1] = cb
			end
			return
		elseif entry.state == "failed" then
			-- Still inside the failure cooldown window: don't hammer the CLI.
			if now_ms() - (entry.ts or 0) < config.failure_ttl_ms then
				if cb then
					cb(entry)
				end
				return
			end
			-- TTL expired: fall through and re-fetch.
		end
	end

	cache[k] = { state = "pending", columns = {}, callbacks = cb and { cb } or {}, dataset = dataset }
	if active_jobs < config.max_jobs then
		run_job(dataset)
	else
		pending_queue[#pending_queue + 1] = dataset
	end
end

-- Public: drop all cached results (and stop in-flight jobs).
function M.clear()
	for _, e in pairs(cache) do
		if e.job_id then
			pcall(vim.fn.jobstop, e.job_id)
		end
	end
	for _, e in pairs(list_cache) do
		if e.job_id then
			pcall(vim.fn.jobstop, e.job_id)
		end
	end
	cache = {}
	pending_queue = {}
	active_jobs = 0
	list_cache = {}
	list_queue = {}
	list_active = 0
end

function M.config()
	return config
end

function M.setup(opts)
	opts = opts or {}
	for _, key in ipairs({ "platform", "origin" }) do
		if type(opts[key]) == "string" and opts[key] ~= "" then
			config[key] = opts[key]
		end
	end
	for _, key in ipairs({ "timeout_ms", "max_jobs", "failure_ttl_ms", "list_count", "list_min_prefix", "list_max_jobs" }) do
		local v = tonumber(opts[key])
		if v then
			config[key] = v
		end
	end

	-- :MetaSchemaRefresh — clear the cache, then re-warm the datasets referenced
	-- by the current buffer so completion is ready again.
	vim.api.nvim_create_user_command("MetaSchemaRefresh", function()
		M.clear()
		local ok, datasets = pcall(function()
			return sqld.scan(0)
		end)
		local n = 0
		if ok then
			for _, ds in ipairs(datasets) do
				M.fetch(ds)
				n = n + 1
			end
		end
		vim.notify(
			string.format("meta schema cache cleared; re-warming %d dataset%s", n, n == 1 and "" or "s"),
			vim.log.levels.INFO,
			{ title = "Meta" }
		)
	end, { desc = "Clear and re-warm the meta schema column cache" })

	-- :MetaSchemaStatus — quick diagnostics of what's cached.
	vim.api.nvim_create_user_command("MetaSchemaStatus", function()
		local lines = {}
		for k, e in pairs(cache) do
			lines[#lines + 1] = string.format("%s  [%s] %d cols", k, e.state, #(e.columns or {}))
		end
		table.sort(lines)
		if #lines == 0 then
			lines = { "meta schema cache is empty." }
		end
		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Meta" })
	end, { desc = "Show the meta schema column cache status" })
end

return M
