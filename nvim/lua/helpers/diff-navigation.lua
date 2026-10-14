local M = {}
local origins = {}
local pending = {}
local restoring = false

local function context()
	local lifecycle = package.loaded["codediff.ui.lifecycle"]
	if not lifecycle then
		return
	end
	local tab = vim.api.nvim_get_current_tabpage()
	local session = lifecycle.get_session(tab)
	local win = vim.api.nvim_get_current_win()
	if
		not session
		or session.suspended
		or session.merge
		or not session.panel
		or session.panel.name ~= "explorer"
		or not session.git_root
		or session.modified_revision and session.modified_revision ~= "WORKING"
		or win ~= session.modified_win
	then
		return
	end
	return tab, session, win
end

local function selected_path(session)
	local file = session.panel.data.current_selection
	return file and require("codediff.core.path").make_ref(file.path, session.git_root).absolute
end

local function find_file(session, name)
	local data = session.panel.data
	local group = data.current_selection and data.current_selection.group or "unstaged"
	local panel = require("codediff.ui.refresh.panel")
	-- Keep the selected group when a file has both staged and unstaged changes.
	for _, candidate_group in ipairs({ group, "unstaged" }) do
		for _, file in ipairs(data.status_result[candidate_group] or {}) do
			if require("codediff.core.path").make_ref(file.path, session.git_root).absolute == name then
				local entry = vim.tbl_extend("force", file, { group = candidate_group })
				local comparison = panel.comparison(session.panel, entry)
				if
					comparison
					and not comparison.modified_revision
					and not comparison.conflict
					and comparison.single_side ~= "original"
				then
					return entry
				end
			end
		end
	end
end

local function follow(tab, session, win, buf, origin)
	local lifecycle = require("codediff.ui.lifecycle")
	if
		lifecycle.get_session(tab) ~= session
		or vim.api.nvim_get_current_tabpage() ~= tab
		or not vim.api.nvim_win_is_valid(win)
		or vim.api.nvim_get_current_win() ~= win
		or vim.api.nvim_win_get_buf(win) ~= buf
		or vim.bo[buf].buftype ~= ""
	then
		return
	end
	local name = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
	if name == "" or name == selected_path(session) then
		return
	end
	local file = find_file(session, name)
	if file then
		-- Also cancel an unfinished selection when jumping back to the loaded file.
		if not require("codediff.ui.refresh").select(tab, file, { no_jump = true, force = true }) then
			vim.notify(
				"Could not open the target file in CodeDiff",
				vim.log.levels.ERROR,
				{ title = "CodeDiff navigation" }
			)
		end
		return
	end
	if not origin or not vim.api.nvim_buf_is_valid(origin.buf) then
		vim.notify(
			"Could not restore the CodeDiff pane for source navigation",
			vim.log.levels.ERROR,
			{ title = "CodeDiff navigation" }
		)
		return
	end
	if session.refresh and session.refresh.loading then
		local previous = find_file(session, vim.fs.normalize(vim.api.nvim_buf_get_name(origin.buf)))
		if
			not previous or not require("codediff.ui.refresh").select(tab, previous, { no_jump = true, force = true })
		then
			vim.notify(
				"Could not cancel the pending CodeDiff selection",
				vim.log.levels.ERROR,
				{ title = "CodeDiff navigation" }
			)
			return
		end
	end

	-- A new tab copies the source window's native jump list.
	local folds = session.compact_saved_fold_state and session.compact_saved_fold_state[win]
	restoring = true
	local ok, err = xpcall(function()
		vim.cmd("tab split")
		vim.wo.scrollbind = false
		vim.wo.cursorbind = false
		vim.wo.winbar = ""
		for option, value in pairs(folds or {}) do
			vim.wo[option] = value
		end
		vim.api.nvim_win_set_buf(win, origin.buf)
		vim.api.nvim_win_call(win, function()
			vim.fn.winrestview(origin.view)
		end)
	end, debug.traceback)
	restoring = false
	if not ok then
		vim.notify(err, vim.log.levels.ERROR, { title = "CodeDiff navigation" })
	end
end

function M.setup()
	local group = vim.api.nvim_create_augroup("codediff_navigation", { clear = true })
	vim.api.nvim_create_autocmd("BufLeave", {
		group = group,
		callback = function(args)
			if restoring then
				return
			end
			local _, session, win = context()
			if session and args.buf == session.modified_bufnr then
				origins[win] = { buf = args.buf, view = vim.fn.winsaveview() }
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(args)
			if restoring then
				return
			end
			local tab, session, win = context()
			if not session or vim.bo[args.buf].buftype ~= "" then
				return
			end
			local request = {}
			pending[tab] = request
			local origin = origins[win]
			vim.schedule(function()
				if pending[tab] ~= request then
					return
				end
				pending[tab] = nil
				follow(tab, session, win, args.buf, origin)
			end)
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			origins[tonumber(args.match)] = nil
		end,
	})
end

return M
