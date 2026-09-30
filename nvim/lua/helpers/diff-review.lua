local M = {}
local namespace = vim.api.nvim_create_namespace("diff_review")
local comments = {}

local function trim(value)
	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "Diff review" })
end

local function normalize_repo_path(git_root, path)
	local root = vim.fs.normalize(git_root):gsub("/+$", "")
	root = root ~= "" and root or "/"
	local normalized = vim.fs.normalize(path):gsub("^%./", "")
	local prefix = root == "/" and root or (root .. "/")
	if normalized:sub(1, #prefix) == prefix then
		return normalized:sub(#prefix + 1)
	end
	return normalized
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

	local git_root = vim.fs.normalize(session.git_root):gsub("/+$", "")
	git_root = git_root ~= "" and git_root or "/"
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
	local lifecycle = require("codediff.ui.lifecycle")
	for tabpage in pairs(require("codediff.ui.lifecycle.session").get_active_diffs()) do
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

local function wrap_text(text, width)
	local lines = {}
	for raw_line in (text .. "\n"):gmatch("(.-)\n") do
		local line = ""
		for word in raw_line:gmatch("%S+") do
			local candidate = line == "" and word or (line .. " " .. word)
			if line ~= "" and vim.fn.strdisplaywidth(candidate) > width then
				table.insert(lines, line)
				line = word
			else
				line = candidate
			end
		end
		table.insert(lines, line)
	end
	return lines
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
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	if line_count == 0 then
		return
	end
	for _, comment in ipairs(comments) do
		if comment_matches_context(comment, context) and comment.line <= line_count then
			local anchor_line = math.max(0, math.min(comment.line_end - 1, line_count - 1))
			local text_lines = wrap_text(comment.text, 60)
			local width = 0
			for _, line in ipairs(text_lines) do
				width = math.max(width, vim.fn.strdisplaywidth(line))
			end
			local virtual_lines = { { { "  ╭" .. string.rep("─", width + 2) .. "╮", "DiffReviewComment" } } }
			for _, line in ipairs(text_lines) do
				local padding = string.rep(" ", width - vim.fn.strdisplaywidth(line))
				table.insert(virtual_lines, { { "  │ " .. line .. padding .. " │", "DiffReviewComment" } })
			end
			table.insert(virtual_lines, { { "  ╰" .. string.rep("─", width + 2) .. "╯", "DiffReviewComment" } })
			vim.api.nvim_buf_set_extmark(bufnr, namespace, anchor_line, 0, {
				sign_text = "",
				sign_hl_group = "DiagnosticSignInfo",
				strict = false,
				virt_lines = virtual_lines,
			})
		end
	end
end

local function render_all()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		render_buffer(bufnr)
	end
end
local function edit_comment(default, on_submit)
	local width = math.max(1, math.min(80, vim.o.columns - 8))
	local height = math.max(1, math.min(10, vim.o.lines - 8))
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

	if default then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(default, "\n", { plain = true }))
	end

	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		elseif vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end
	local function submit()
		local text = trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
		if text ~= "" then
			close()
			on_submit(text)
		end
	end

	vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf, desc = "Save review comment" })
	vim.keymap.set("n", "q", close, { buffer = buf, desc = "Cancel review comment" })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf, desc = "Cancel review comment" })
	if default then
		local last_line = vim.api.nvim_buf_line_count(buf)
		local last_text = vim.api.nvim_buf_get_lines(buf, last_line - 1, last_line, false)[1]
		vim.api.nvim_win_set_cursor(win, { last_line, #(last_text or "") })
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
		line = vim.fn.line("v")
		line_end = vim.api.nvim_win_get_cursor(0)[1]
		if line > line_end then
			line, line_end = line_end, line
		end
	end

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	line = math.max(1, math.min(line, line_count))
	line_end = math.max(line, math.min(line_end, line_count))
	local source = vim.api.nvim_buf_get_lines(bufnr, line - 1, line_end, false)
	edit_comment(nil, function(text)
		table.insert(comments, {
			git_root = context.git_root,
			path = context.path,
			file_key = context.file_key,
			side = context.side,
			line = line,
			line_end = line_end,
			source = source,
			text = text,
		})
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
	for _, candidate in ipairs(lines) do
		if direction * (candidate - current_line) > 0 then
			target = candidate
			if direction > 0 then
				break
			end
		end
	end

	vim.api.nvim_win_set_cursor(0, { target, 0 })
	vim.cmd.normal({ args = { "zz" }, bang = true })
end

function M.delete_at_cursor()
	local _, index, bufnr, err = comment_at_cursor()
	if not index then
		notify(err, vim.log.levels.WARN)
		return
	end

	table.remove(comments, index)
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

	edit_comment(comment.text, function(text)
		comment.text = text
		render_buffer(bufnr)
	end)
end

local function clear_root(git_root)
	comments = vim.tbl_filter(function(comment)
		return comment.git_root ~= git_root
	end, comments)
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

local function list_copilot_panes()
	if not vim.env.TMUX or not vim.env.TMUX_PANE then
		return nil, "Neovim is not running inside tmux"
	end

	local output, list_err = run({
		"tmux",
		"list-panes",
		"-s",
		"-t",
		vim.env.TMUX_PANE,
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

	return panes
end

local function build_prompt(root_comments)
	table.sort(root_comments, function(left, right)
		local left_key = string.format("%s\0%s\0%09d", left.path, left.side, left.line)
		local right_key = string.format("%s\0%s\0%09d", right.path, right.side, right.line)
		return left_key < right_key
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
		table.insert(lines, "   Comment: " .. comment.text)
		table.insert(lines, "   Code:")
		for _, source_line in ipairs(comment.source) do
			table.insert(lines, "     " .. source_line)
		end
		table.insert(lines, "")
	end

	return table.concat(lines, "\n")
end

local function send_to_pane(pane, prompt, git_root, count)
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
	local _, submit_err = run({ "tmux", "send-keys", "-t", pane.id, "Enter" })
	if submit_err then
		notify("Review prompt was pasted but not sent: " .. submit_err, vim.log.levels.ERROR)
		return
	end
	clear_root(git_root)
	notify(string.format("%d review comment%s sent to Copilot", count, count == 1 and "" or "s"))
end

function M.send()
	local context, err = get_context(vim.api.nvim_get_current_buf())
	if not context then
		notify(err, vim.log.levels.WARN)
		return
	end

	local root_comments = vim.tbl_filter(function(comment)
		return comment.git_root == context.git_root
	end, comments)
	if #root_comments == 0 then
		notify("No review comments to send", vim.log.levels.WARN)
		return
	end

	local prompt = build_prompt(root_comments)
	local panes, pane_err = list_copilot_panes()
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

local function attach_buffer(bufnr)
	if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	if not get_context(bufnr) then
		return
	end
	if not vim.b[bufnr].diff_review_attached then
		vim.b[bufnr].diff_review_attached = true
		local mappings = {
			{ "n", "<leader>gc", function() M.add(false) end, "Add diff review comment" },
			{ "x", "<leader>gc", function() M.add(true) end, "Add diff review comment" },
			{ "n", "<leader>ge", M.edit_at_cursor, "Edit diff review comment" },
			{ "n", "<leader>gD", M.delete_at_cursor, "Delete diff review comment" },
			{ "n", "<leader>gs", M.send, "Send review comments to Copilot" },
			{ "n", "<leader>gC", M.clear, "Clear diff review comments" },
			{ "n", "]r", function() jump_to_comment(1) end, "Next diff review comment" },
			{ "n", "[r", function() jump_to_comment(-1) end, "Previous diff review comment" },
		}
		for _, map in ipairs(mappings) do
			vim.keymap.set(map[1], map[2], map[3], { buffer = bufnr, desc = map[4] })
		end
	end

	render_buffer(bufnr)
end

local function setup_highlights()
	vim.api.nvim_set_hl(0, "DiffReviewComment", { default = true, link = "DiagnosticInfo" })
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
					for _, bufnr in ipairs({ session.original_bufnr, session.modified_bufnr }) do
						attach_buffer(bufnr)
					end
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

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = setup_highlights,
	})
end

function M.setup()
	setup_highlights()
	setup_autocmds()
end
return M
