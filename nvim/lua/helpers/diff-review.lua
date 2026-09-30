local M = {}

local namespace = vim.api.nvim_create_namespace("diff_review")
local comments = {}
local rendered_buffers = {}
local next_id = 1
local persist_comments = function() end
local restore_comments = function() end

local function trim(value)
	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "Diff review" })
end

local function normalize_repo_path(git_root, path)
	local root = vim.fs.normalize(git_root):gsub("/+$", "")
	if root == "" then
		root = "/"
	end
	local normalized = vim.fs.normalize(path):gsub("^%./", "")
	local prefix = root == "/" and root or (root .. "/")
	if normalized:sub(1, #prefix) == prefix then
		return normalized:sub(#prefix + 1)
	end
	return normalized
end

local function normalize_git_root(git_root)
	local normalized = vim.fs.normalize(git_root):gsub("/+$", "")
	return normalized ~= "" and normalized or "/"
end

local function session_path(ref)
	if type(ref) == "table" then
		return ref.relative ~= "" and ref.relative or ref.absolute
	end
	return ref
end

local function get_context(bufnr)
	local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
	if not ok then
		return nil, "CodeDiff is not loaded"
	end

	local tabpage = lifecycle.find_tabpage_by_buffer(bufnr)
	local session = tabpage and lifecycle.get_session(tabpage) or nil
	if not session then
		return nil, "Not in a CodeDiff buffer"
	end

	local side
	local path
	local original_path = session_path(session.original or session.original_path)
	local modified_path = session_path(session.modified or session.modified_path)
	if bufnr == session.original_bufnr and session.layout ~= "inline" then
		side = "old"
		path = original_path
	elseif bufnr == session.modified_bufnr then
		side = "new"
		path = modified_path
	else
		return nil, "Comments are only supported in CodeDiff's old and new panes"
	end

	if not session.git_root or not path or path == "" then
		return nil, "Select a file in CodeDiff before adding a comment"
	end

	local git_root = normalize_git_root(session.git_root)
	return {
		bufnr = bufnr,
		git_root = git_root,
		path = normalize_repo_path(git_root, path),
		file_key = normalize_repo_path(git_root, modified_path or path),
		side = side,
	}
end

local function comment_matches_context(comment, context)
	return comment.git_root == context.git_root and comment.path == context.path and comment.side == context.side
end

local function refresh_sidebars()
	local ok_sessions, sessions = pcall(require, "codediff.ui.lifecycle.session")
	local ok_lifecycle, lifecycle = pcall(require, "codediff.ui.lifecycle")
	if not ok_sessions or not ok_lifecycle then
		return
	end

	for tabpage in pairs(sessions.get_active_diffs()) do
		local panel = lifecycle.get_panel_view(tabpage)
		if panel and panel.tree then
			panel.tree:render()
		end
	end
end

function M.review_count(path)
	local count = 0
	for _, comment in ipairs(comments) do
		if comment.file_key == path then
			count = count + 1
		end
	end
	return count
end

local function render_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
		return
	end

	local context = get_context(bufnr)
	if not context then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
	rendered_buffers[bufnr] = true

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	if line_count == 0 then
		return
	end
	for _, comment in ipairs(comments) do
		if comment_matches_context(comment, context) and comment.line <= line_count then
			local text_lines = vim.split(comment.text, "\n", { plain = true })
			local bubble_width = 0
			for _, line in ipairs(text_lines) do
				bubble_width = math.max(bubble_width, vim.fn.strdisplaywidth(line))
			end

			local virtual_lines = {}
			table.insert(virtual_lines, {
				{ "  ╭" .. string.rep("─", bubble_width + 2) .. "╮", "DiffReviewBubbleBorder" },
			})
			for _, line in ipairs(text_lines) do
				local padding = string.rep(" ", bubble_width - vim.fn.strdisplaywidth(line))
				table.insert(virtual_lines, {
					{ "  │ ", "DiffReviewBubbleBorder" },
					{ line .. padding, "DiffReviewBubbleText" },
					{ " │", "DiffReviewBubbleBorder" },
				})
			end
			table.insert(virtual_lines, {
				{ "  ╰" .. string.rep("─", bubble_width + 2) .. "╯", "DiffReviewBubbleBorder" },
			})

			local anchor_line = math.max(0, math.min(comment.line_end - 1, line_count - 1))
			vim.api.nvim_buf_set_extmark(bufnr, namespace, anchor_line, 0, {
				sign_text = "",
				sign_hl_group = "DiagnosticSignInfo",
				strict = false,
				virt_lines = virtual_lines,
				virt_lines_above = false,
			})
		end
	end
end

local function render_all()
	for bufnr in pairs(rendered_buffers) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			render_buffer(bufnr)
		else
			rendered_buffers[bufnr] = nil
		end
	end
end

local function close_editor(win, buf)
	if vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

local function open_editor(on_submit, initial_text)
	local width = math.min(80, math.max(40, vim.o.columns - 8))
	local height = math.min(12, math.max(5, vim.o.lines - 8))
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = " Review comment ",
		title_pos = "center",
	})

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "markdown"
	vim.wo[win].wrap = true
	vim.wo[win].linebreak = true
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false

	if initial_text and initial_text ~= "" then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(initial_text, "\n", { plain = true }))
	end

	local function submit()
		local text = trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
		if text == "" then
			notify("Comment cannot be empty", vim.log.levels.WARN)
			return
		end
		close_editor(win, buf)
		vim.schedule(function()
			on_submit(text)
		end)
	end

	local function cancel()
		close_editor(win, buf)
	end

	vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf, desc = "Save review comment" })
	vim.keymap.set("n", "q", cancel, { buffer = buf, desc = "Cancel review comment" })
	vim.keymap.set("n", "<Esc>", cancel, { buffer = buf, desc = "Cancel review comment" })

	if initial_text and initial_text ~= "" then
		local last_line = vim.api.nvim_buf_line_count(buf)
		local last_text = vim.api.nvim_buf_get_lines(buf, last_line - 1, last_line, false)[1] or ""
		vim.api.nvim_win_set_cursor(win, { last_line, #last_text })
	end
	vim.cmd.startinsert()
end

function M.add(use_visual_range)
	local bufnr = vim.api.nvim_get_current_buf()
	local context, err = get_context(bufnr)
	if not context then
		notify(err, vim.log.levels.WARN)
		return
	end

	local line = vim.api.nvim_win_get_cursor(0)[1]
	local line_end = line
	if use_visual_range then
		local visual_start = vim.fn.line("v")
		if visual_start > 0 then
			line = visual_start
			line_end = vim.api.nvim_win_get_cursor(0)[1]
		else
			line = vim.fn.line("'<")
			line_end = vim.fn.line("'>")
		end
		if line > line_end then
			line, line_end = line_end, line
		end
	end

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	line = math.max(1, math.min(line, line_count))
	line_end = math.max(line, math.min(line_end, line_count))
	local source = vim.api.nvim_buf_get_lines(bufnr, line - 1, line_end, false)
	open_editor(function(text)
		table.insert(comments, {
			id = next_id,
			git_root = context.git_root,
			path = context.path,
			file_key = context.file_key,
			side = context.side,
			line = line,
			line_end = line_end,
			source = source,
			text = text,
		})
		next_id = next_id + 1
		persist_comments()
		render_buffer(bufnr)
		refresh_sidebars()
	end)
end

local function comment_at_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local context, err = get_context(bufnr)
	if not context then
		return nil, nil, nil, err
	end

	local line = vim.api.nvim_win_get_cursor(0)[1]
	for index = #comments, 1, -1 do
		local comment = comments[index]
		if comment_matches_context(comment, context) and line >= comment.line and line <= comment.line_end then
			return comment, index, bufnr
		end
	end

	return nil, nil, bufnr, "No review comment at the cursor"
end

local function jump_to_comment(direction)
	local bufnr = vim.api.nvim_get_current_buf()
	local context, err = get_context(bufnr)
	if not context then
		notify(err, vim.log.levels.WARN)
		return
	end

	local lines = {}
	local seen = {}
	for _, comment in ipairs(comments) do
		if comment_matches_context(comment, context) and not seen[comment.line] then
			seen[comment.line] = true
			table.insert(lines, comment.line)
		end
	end
	table.sort(lines)

	if #lines == 0 then
		notify("No review comments in this diff pane", vim.log.levels.WARN)
		return
	end

	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local target = direction > 0 and lines[1] or lines[#lines]
	if direction > 0 then
		for _, line in ipairs(lines) do
			if line > current_line then
				target = line
				break
			end
		end
	else
		for index = #lines, 1, -1 do
			if lines[index] < current_line then
				target = lines[index]
				break
			end
		end
	end

	vim.api.nvim_win_set_cursor(0, { target, 0 })
	vim.cmd.normal({ args = { "zz" }, bang = true })
end

function M.next_comment()
	jump_to_comment(1)
end

function M.previous_comment()
	jump_to_comment(-1)
end

function M.delete_at_cursor()
	local _, index, bufnr, err = comment_at_cursor()
	if not index then
		notify(err, vim.log.levels.WARN)
		return
	end

	table.remove(comments, index)
	persist_comments()
	render_buffer(bufnr)
	refresh_sidebars()
	notify("Comment deleted")
end

function M.edit_at_cursor()
	local comment, _, bufnr, err = comment_at_cursor()
	if not comment then
		notify(err, vim.log.levels.WARN)
		return
	end

	open_editor(function(text)
		comment.text = text
		persist_comments()
		render_buffer(bufnr)
	end, comment.text)
end

local function clear_root(git_root)
	for index = #comments, 1, -1 do
		if comments[index].git_root == git_root then
			table.remove(comments, index)
		end
	end
	persist_comments()
	render_all()
	refresh_sidebars()
end

function M.clear()
	local context, err = get_context(vim.api.nvim_get_current_buf())
	if not context then
		notify(err, vim.log.levels.WARN)
		return
	end

	clear_root(context.git_root)
	notify("Review comments cleared")
end

local function run(command, options)
	options = vim.tbl_extend("force", { text = true }, options or {})
	local result = vim.system(command, options):wait()
	if result.code ~= 0 then
		local message = trim(result.stderr or "")
		return nil, message ~= "" and message or ("Command failed with exit code " .. result.code)
	end
	return trim(result.stdout or "")
end

local tmux_review_option = "@nvim-diff-review-comments"

local function current_tmux_session()
	if not vim.env.TMUX or not vim.env.TMUX_PANE then
		return nil
	end

	return run({
		"tmux",
		"display-message",
		"-p",
		"-t",
		vim.env.TMUX_PANE,
		"#{session_name}",
	})
end

persist_comments = function()
	local session = current_tmux_session()
	if not session then
		return
	end

	if #comments == 0 then
		run({ "tmux", "set-option", "-q", "-u", "-t", session, tmux_review_option })
		return
	end

	local encoded = vim.json.encode({
		version = 1,
		comments = comments,
		next_id = next_id,
	})
	local _, err = run({ "tmux", "set-option", "-q", "-t", session, tmux_review_option, encoded })
	if err then
		notify("Could not persist review comments: " .. err, vim.log.levels.ERROR)
	end
end

restore_comments = function()
	local session = current_tmux_session()
	if not session then
		return
	end

	local encoded = run({ "tmux", "show-options", "-qv", "-t", session, tmux_review_option })
	if not encoded or encoded == "" then
		return
	end

	local ok, state = pcall(vim.json.decode, encoded)
	if not ok or type(state) ~= "table" or type(state.comments) ~= "table" then
		notify("Could not restore persisted review comments", vim.log.levels.WARN)
		return
	end

	local restored = {}
	local restored_next_id = 1
	local skipped = 0
	for _, comment in ipairs(state.comments) do
		local valid = type(comment) == "table"
		local id = valid and tonumber(comment.id) or nil
		local line = valid and tonumber(comment.line) or nil
		local line_end = valid and tonumber(comment.line_end) or nil
		valid = valid
			and id
			and id >= 1
			and id % 1 == 0
			and type(comment.git_root) == "string"
			and comment.git_root ~= ""
			and type(comment.path) == "string"
			and comment.path ~= ""
			and type(comment.file_key) == "string"
			and comment.file_key ~= ""
			and (comment.side == "old" or comment.side == "new")
			and line
			and line >= 1
			and line % 1 == 0
			and line_end
			and line_end >= line
			and line_end % 1 == 0
			and type(comment.source) == "table"
			and type(comment.text) == "string"
			and trim(comment.text) ~= ""

		local source = {}
		if valid then
			for _, source_line in ipairs(comment.source) do
				if type(source_line) ~= "string" then
					valid = false
					break
				end
				table.insert(source, source_line)
			end
		end

		if valid then
			local git_root = normalize_git_root(comment.git_root)
			table.insert(restored, {
				id = id,
				git_root = git_root,
				path = normalize_repo_path(git_root, comment.path),
				file_key = normalize_repo_path(git_root, comment.file_key),
				side = comment.side,
				line = line,
				line_end = line_end,
				source = source,
				text = comment.text,
			})
			restored_next_id = math.max(restored_next_id, id + 1)
		else
			skipped = skipped + 1
		end
	end

	comments = restored
	local persisted_next_id = tonumber(state.next_id)
	if not persisted_next_id or persisted_next_id < 1 or persisted_next_id % 1 ~= 0 then
		persisted_next_id = 1
	end
	next_id = math.max(persisted_next_id, restored_next_id)
	if skipped > 0 then
		local suffix = skipped == 1 and "" or "s"
		notify(string.format("Ignored %d invalid persisted review comment%s", skipped, suffix), vim.log.levels.WARN)
	end
end

local function copilot_status(pane_id)
	local copilot_home = vim.env.COPILOT_HOME or vim.fn.expand("~/.copilot")
	local state_path = copilot_home .. "/agent-status/" .. pane_id:gsub("^%%", "") .. ".json"
	local file = io.open(state_path, "r")
	if not file then
		return nil
	end

	local contents = file:read("*a")
	file:close()
	local ok, state = pcall(vim.json.decode, contents)
	return ok and state or nil
end

local function list_copilot_panes(git_root)
	if not vim.env.TMUX or not vim.env.TMUX_PANE then
		return nil, "Neovim is not running inside tmux"
	end

	local session, session_err = run({
		"tmux",
		"display-message",
		"-p",
		"-t",
		vim.env.TMUX_PANE,
		"#{session_name}",
	})
	if not session then
		return nil, session_err
	end

	local output, list_err = run({
		"tmux",
		"list-panes",
		"-t",
		session,
		"-F",
		"#{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}",
	})
	if not output then
		return nil, list_err
	end

	local panes = {}
	for _, row in ipairs(vim.split(output, "\n", { trimempty = true })) do
		local fields = vim.split(row, "\t", { plain = true })
		local pane_id, command, title, path = unpack(fields)
		local identity = ((command or "") .. " " .. (title or "")):lower()
		if pane_id and pane_id ~= vim.env.TMUX_PANE and identity:find("copilot", 1, true) then
			table.insert(panes, {
				id = pane_id,
				command = command,
				title = title,
				path = path,
			})
		end
	end

	table.sort(panes, function(left, right)
		if (left.path == git_root) ~= (right.path == git_root) then
			return left.path == git_root
		end
		return left.id < right.id
	end)

	return panes
end

local function build_prompt(root_comments)
	table.sort(root_comments, function(left, right)
		if left.path ~= right.path then
			return left.path < right.path
		end
		if left.side ~= right.side then
			return left.side < right.side
		end
		if left.line ~= right.line then
			return left.line < right.line
		end
		return left.id < right.id
	end)

	local lines = {
		"Please address the following review comments in the current working tree.",
		"Inspect the diff, implement the requested changes, and preserve unrelated work.",
		"",
	}

	for index, comment in ipairs(root_comments) do
		local line_range = tostring(comment.line)
		if comment.line_end ~= comment.line then
			line_range = line_range .. "-" .. comment.line_end
		end
		if comment.side == "old" then
			line_range = "~" .. line_range
		end

		table.insert(lines, string.format("%d. %s:%s [%s side]", index, comment.path, line_range, comment.side))
		for _, text_line in ipairs(vim.split(comment.text, "\n", { plain = true })) do
			table.insert(lines, "   Comment: " .. text_line)
		end
		table.insert(lines, "   Code:")
		for _, source_line in ipairs(comment.source) do
			table.insert(lines, "     " .. source_line)
		end
		table.insert(lines, "")
	end

	return table.concat(lines, "\n")
end

local function open_confirmation(prompt, count, on_confirm)
	local width = math.min(100, math.max(50, vim.o.columns - 8))
	local height = math.min(30, math.max(10, vim.o.lines - 8))
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = string.format(" Review comments (%d) ", count),
		title_pos = "center",
		footer = " Enter/y: send  q/Esc: cancel ",
		footer_pos = "center",
	})

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "markdown"
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(prompt, "\n", { plain = true }))
	vim.bo[buf].modifiable = false
	vim.wo[win].wrap = true
	vim.wo[win].linebreak = true
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].cursorline = true

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		close_editor(win, buf)
	end

	local function confirm()
		close()
		vim.schedule(on_confirm)
	end

	vim.keymap.set("n", "<CR>", confirm, { buffer = buf, desc = "Send review comments" })
	vim.keymap.set("n", "y", confirm, { buffer = buf, desc = "Send review comments" })
	vim.keymap.set("n", "q", close, { buffer = buf, desc = "Cancel review submission" })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf, desc = "Cancel review submission" })
end

local function send_to_pane(pane, prompt, git_root, count)
	local state = copilot_status(pane.id)
	if state and state.status == "awaiting" then
		notify("Copilot is awaiting input; resolve it before sending review comments", vim.log.levels.WARN)
		return
	end

	local buffer_name = "nvim-diff-review-" .. vim.fn.getpid()
	local _, load_err = run({ "tmux", "load-buffer", "-b", buffer_name, "-" }, { stdin = prompt })
	if load_err then
		notify("Could not load the review prompt: " .. load_err, vim.log.levels.ERROR)
		return
	end

	local _, paste_err = run({ "tmux", "paste-buffer", "-d", "-b", buffer_name, "-t", pane.id })
	if paste_err then
		notify("Could not paste into Copilot: " .. paste_err, vim.log.levels.ERROR)
		return
	end

	local submit_key = state and state.status == "working" and "C-q" or "Enter"
	local _, submit_err = run({ "tmux", "send-keys", "-t", pane.id, submit_key })
	if submit_err then
		notify("Review prompt was pasted but not submitted: " .. submit_err, vim.log.levels.ERROR)
		return
	end

	clear_root(git_root)
	local action = submit_key == "C-q" and "queued for" or "sent to"
	notify(string.format("%d review comment%s %s Copilot", count, count == 1 and "" or "s", action))
end

function M.send(show_confirmation)
	local context, err = get_context(vim.api.nvim_get_current_buf())
	if not context then
		notify(err, vim.log.levels.WARN)
		return
	end

	local root_comments = {}
	for _, comment in ipairs(comments) do
		if comment.git_root == context.git_root then
			table.insert(root_comments, vim.deepcopy(comment))
		end
	end
	if #root_comments == 0 then
		notify("No review comments to send", vim.log.levels.WARN)
		return
	end

	local prompt = build_prompt(root_comments)
	local function submit()
		local panes, pane_err = list_copilot_panes(context.git_root)
		if not panes then
			notify("Could not find Copilot: " .. pane_err, vim.log.levels.ERROR)
			return
		end
		if #panes == 0 then
			notify("No Copilot CLI pane found in this tmux session", vim.log.levels.WARN)
			return
		end
		if #panes == 1 then
			send_to_pane(panes[1], prompt, context.git_root, #root_comments)
			return
		end

		vim.ui.select(panes, {
			prompt = "Send review comments to Copilot pane:",
			format_item = function(pane)
				return string.format("%s  %s  %s", pane.id, pane.path or "", pane.title or pane.command or "")
			end,
		}, function(pane)
			if pane then
				send_to_pane(pane, prompt, context.git_root, #root_comments)
			end
		end)
	end

	if show_confirmation then
		open_confirmation(prompt, #root_comments, submit)
	else
		submit()
	end
end

function M.review_summary()
	M.send(true)
end

local function attach_buffer(bufnr)
	if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	if not get_context(bufnr) then
		return
	end

	if not vim.b[bufnr].diff_review_attached then
		vim.b[bufnr].diff_review_attached = true
		vim.keymap.set("n", "<leader>gc", function()
			M.add(false)
		end, { buffer = bufnr, desc = "Add diff review comment" })
		vim.keymap.set("x", "<leader>gc", function()
			M.add(true)
		end, { buffer = bufnr, desc = "Add diff review comment" })
		vim.keymap.set("n", "<leader>ge", M.edit_at_cursor, { buffer = bufnr, desc = "Edit diff review comment" })
		vim.keymap.set("n", "<leader>gD", M.delete_at_cursor, { buffer = bufnr, desc = "Delete diff review comment" })
		vim.keymap.set("n", "<leader>gS", M.review_summary, { buffer = bufnr, desc = "Review comment summary" })
		vim.keymap.set("n", "<leader>gs", M.send, { buffer = bufnr, desc = "Send review comments to Copilot" })
		vim.keymap.set("n", "<leader>gC", M.clear, { buffer = bufnr, desc = "Clear diff review comments" })
		vim.keymap.set("n", "]r", M.next_comment, { buffer = bufnr, desc = "Next diff review comment" })
		vim.keymap.set("n", "[r", M.previous_comment, { buffer = bufnr, desc = "Previous diff review comment" })
	end

	render_buffer(bufnr)
end

local function setup_highlights()
	vim.api.nvim_set_hl(0, "DiffReviewBubbleBorder", { default = true, link = "DiagnosticInfo" })
	vim.api.nvim_set_hl(0, "DiffReviewBubbleText", { default = true, link = "NormalFloat" })
	vim.api.nvim_set_hl(0, "DiffReviewSidebarBadge", { default = true, link = "DiagnosticInfo" })
end

local function setup_autocmds()
	local group = vim.api.nvim_create_augroup("diff_review", { clear = true })

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
		callback = function(args)
			local tabpage = args.data and args.data.tabpage
			vim.schedule(function()
				local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
				local session = ok and tabpage and lifecycle.get_session(tabpage) or nil
				if session then
					attach_buffer(session.original_bufnr)
					attach_buffer(session.modified_bufnr)
				end
			end)
		end,
	})

	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(args)
			if not package.loaded["codediff.ui.lifecycle"] then
				return
			end
			attach_buffer(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		callback = function(args)
			rendered_buffers[args.buf] = nil
		end,
	})

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = setup_highlights,
	})
end

function M.setup()
	restore_comments()
	setup_highlights()
	setup_autocmds()
end

return M
