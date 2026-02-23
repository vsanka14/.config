-- Inline git blame: shows author, date, and summary as virtual text at EOL.
-- Exposes actions to open the blame commit diff (DiffviewOpen) and the PR in browser.
local M = {}
local ns = vim.api.nvim_create_namespace("inline_blame")
local cache = {} -- [bufnr] = { line, text, hash }
local active_job = nil

function M.clear(bufnr) vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1) end
function M.clean_cache(bufnr) cache[bufnr] = nil end

local function render(bufnr, line, text)
	M.clear(bufnr)
	if text then
		vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
			virt_text = { { text, "Comment" } }, virt_text_pos = "eol",
		})
	end
end

function M.show()
	local bufnr = vim.api.nvim_get_current_buf()
	local file = vim.api.nvim_buf_get_name(bufnr)
	if file == "" or vim.bo[bufnr].buftype ~= "" then return end

	local line = vim.api.nvim_win_get_cursor(0)[1]
	local line_text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
	if not line_text or line_text:match("^%s*$") then M.clear(bufnr); return end

	if cache[bufnr] and cache[bufnr].line == line then render(bufnr, line, cache[bufnr].text); return end

	if active_job then pcall(vim.fn.jobstop, active_job); active_job = nil end

	local stdout = {}
	active_job = vim.fn.jobstart(
		{ "git", "blame", "-L", line .. "," .. line, "--porcelain", "--", file },
		{
			stdout_buffered = true,
			on_stdout = function(_, data) stdout = data end,
			on_exit = function(_, code)
				active_job = nil
				vim.schedule(function()
					if code ~= 0 or not stdout or #stdout == 0 then return end
					if not vim.api.nvim_buf_is_valid(bufnr) then return end
					if vim.api.nvim_get_current_buf() ~= bufnr or vim.api.nvim_win_get_cursor(0)[1] ~= line then return end

					local hash = stdout[1] and stdout[1]:match("^(%x+)")
					local author, time_val, summary
					for _, l in ipairs(stdout) do
						if l:match("^author ") then author = l:sub(8)
						elseif l:match("^author%-time ") then time_val = tonumber(l:sub(13))
						elseif l:match("^summary ") then summary = l:sub(9) end
					end

					if not author or author == "Not Committed Yet" then
						cache[bufnr] = { line = line }; M.clear(bufnr); return
					end

					local text = string.format(" %s, %s - %s", author, os.date("%Y-%m-%d", time_val), summary or "")
					cache[bufnr] = { line = line, text = text, hash = hash }
					render(bufnr, line, text)
				end)
			end,
		}
	)
end

function M.open_commit()
	local entry = cache[vim.api.nvim_get_current_buf()]
	if entry and entry.hash then vim.cmd("DiffviewOpen " .. entry.hash .. "^.." .. entry.hash) end
end

function M.open_pr()
	local bufnr = vim.api.nvim_get_current_buf()
	local entry = cache[bufnr]
	if not entry or not entry.text then return end
	local pr = entry.text:match("#(%d+)")
	if not pr then vim.notify("No PR number found in blame", vim.log.levels.WARN); return end

	vim.fn.jobstart({ "git", "-C", vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":h"), "rev-parse", "--show-toplevel" }, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			local root = data and vim.trim(table.concat(data, ""))
			if not root or root == "" then return end
			vim.schedule(function()
				vim.ui.open("https://github.com/linkedin-multiproduct/" .. vim.fn.fnamemodify(root, ":t") .. "/pull/" .. pr)
			end)
		end,
	})
end

return M
