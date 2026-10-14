local M = {}

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "NeetCode" })
end

--- The problem id is the file name: a NeetCode slug (or a LeetCode slug, which `neetcode` resolves).
---@return string|nil
local function problem_slug()
	local slug = vim.fn.expand("%:t:r")
	return slug:match("^[%w-]+$") and slug or nil
end

local FZF_COLORS = "--color=bg:-1,gutter:-1,bg+:#292e42"

---@param dir string
---@param args string
---@param on_exit? fun()
---@param border? string
---@param keep_open? fun(code: integer): boolean
local function run(dir, args, on_exit, border, keep_open)
	local cmd = ("cd %s && export NEETCODE_DIR=%s FZF_DEFAULT_OPTS=\"$FZF_DEFAULT_OPTS %s\" && %s"):format(
		vim.fn.shellescape(dir),
		vim.fn.shellescape(dir),
		FZF_COLORS,
		args
	)
	require("helpers.float-term").open(cmd, {
		width = 0.85,
		height = 0.8,
		border = border,
		keep_open = keep_open,
		on_exit = on_exit,
	})
end

local function snapshot(dir)
	local files = {}
	for name, kind in vim.fs.dir(dir) do
		if kind == "file" then
			files[name] = vim.uv.fs_stat(dir .. "/" .. name).mtime.sec
		end
	end
	return files
end

--- Run `neetcode <sub> <slug>` for the current file in a floating terminal.
---@param sub string neetcode subcommand (e.g. "exec", "test")
function M.send(sub)
	local slug = problem_slug()
	if not slug then
		return notify("No problem for " .. vim.fn.expand("%:t"), vim.log.levels.WARN)
	end
	vim.cmd("silent update")
	local dir = vim.fn.expand("%:p:h")
	run(dir, ("neetcode %s %s"):format(sub, vim.fn.shellescape(slug)), nil, nil, function()
		return true
	end)
end

local LISTS = { "blind75", "neetcode150", "neetcode250", "all" }

--- Run `neetcode select` (fzf) in a floating terminal, then open the created/updated file.
---@param list? string One of LISTS; when nil, pick one with fzf first.
function M.select(list)
	local dir = vim.fn.getcwd()
	local before = snapshot(dir)
	local cmd
	if list then
		cmd = "neetcode select --no-open --list " .. vim.fn.shellescape(list)
	else
		-- One shell command, so a single float covers both pickers.
		cmd = ("l=$(printf '%%s\\n' %s | fzf --prompt='NeetCode list> ' --layout=reverse) && [ -n \"$l\" ] && neetcode select --no-open --list \"$l\""):format(
			table.concat(LISTS, " ")
		)
	end
	run(dir, cmd, function()
		local after = snapshot(dir)
		local best, best_t
		for name, t in pairs(after) do
			if before[name] == nil or t > before[name] then
				if not best_t or t > best_t then
					best, best_t = name, t
				end
			end
		end
		if not best then
			return notify("No new solution file found in " .. dir, vim.log.levels.WARN)
		end
		vim.cmd.edit(vim.fn.fnameescape(dir .. "/" .. best))
		if before[best] == nil then
			-- Writing triggers conform's format_on_save, so the starter code is formatted.
			vim.cmd("silent write")
		end
	end, "none", function(code)
		return code ~= 0
	end)
end

function M.open_neetcode()
	local slug = problem_slug()
	if not slug then
		return notify("Invalid problem file name: " .. vim.fn.expand("%:t"), vim.log.levels.WARN)
	end
	vim.ui.open(("https://neetcode.io/problems/%s/question"):format(slug))
end

return M
