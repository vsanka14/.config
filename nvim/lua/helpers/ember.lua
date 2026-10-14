local M = {}

-- Helper functions for file operations
local function open_file(file_path)
	vim.cmd("edit " .. vim.fn.fnameescape(file_path))
end

local function file_exists(file_path)
	return vim.fn.filereadable(file_path) == 1
end

local function try_open_file(file_path, error_message)
	if file_exists(file_path) then
		open_file(file_path)
		return true
	end
	if error_message then
		vim.notify(error_message, vim.log.levels.WARN)
	end
	return false
end

local function try_open_first_existing(files, error_message)
	for _, file_path in ipairs(files) do
		if file_exists(file_path) then
			open_file(file_path)
			return true
		end
	end
	vim.notify(error_message, vim.log.levels.WARN)
	return false
end

--- Switch between Ember .hbs and .js/.ts files
function M.go_to_alternate()
	local current_file = vim.fn.expand("%:p")

	if current_file:match("%.hbs$") then
		try_open_first_existing({
			current_file:gsub("%.hbs$", ".js"),
			current_file:gsub("%.hbs$", ".ts"),
		}, "No corresponding .js or .ts file found")
	elseif current_file:match("%.js$") then
		try_open_file(current_file:gsub("%.js$", ".hbs"), "File not found: " .. current_file:gsub("%.js$", ".hbs"))
	elseif current_file:match("%.ts$") then
		try_open_file(current_file:gsub("%.ts$", ".hbs"), "File not found: " .. current_file:gsub("%.ts$", ".hbs"))
	else
		vim.notify("Not an Ember file (.hbs, .js, or .ts)", vim.log.levels.WARN)
	end
end

-- Helper function to replace characters in t-def first quoted string only
local function replace_in_tdef(bufnr, char_map, notify_msg)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	local new_content = content:gsub('({{t%-def%s+")(.-)(")', function(prefix, str_content, suffix)
		local replaced_content = str_content
		for from, to in pairs(char_map) do
			replaced_content = replaced_content:gsub(from, to)
		end
		return prefix .. replaced_content .. suffix
	end)

	if new_content ~= content then
		local new_lines = vim.split(new_content, "\n", { plain = true })
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
		if notify_msg then
			vim.notify(notify_msg, vim.log.levels.INFO)
		end
		return true
	end
	return false
end

function M.convert_unicode_to_char(buf)
	local unicode_to_char = {
		["\\u2019"] = "\u{2019}",
		["\\u201C"] = "\u{201c}",
		["\\u201c"] = "\u{201c}",
		["\\u201D"] = "\u{201d}",
		["\\u201d"] = "\u{201d}",
		["\\u0022"] = '"',
		["\\u0026"] = "&",
	}
	replace_in_tdef(buf, unicode_to_char, "Replaced unicode escapes with actual characters")
end

function M.convert_char_to_unicode(buf)
	local char_to_unicode = { ["\u{2019}"] = "\\u2019", ['"'] = "\\u0022", ["&"] = "\\u0026" }
	replace_in_tdef(buf, char_to_unicode, nil)
end

-- Component resolution for go-to-definition --------------------------------
-- ctags can't follow Ember's filesystem-convention references (and has no
-- Handlebars parser), so map a component invocation under the cursor to the
-- files backing it by path:
--   <ConversionTracking::Header>   -> app/components/conversion-tracking/header.{hbs,js,...}
--   <CampaignDetailsModuleHeader>  -> app/components/campaign-details-module-header.{hbs,...}
--   {{conversion-tracking/header}} -> app/components/conversion-tracking/header.{hbs,...}

-- Extensions a component can live in, template first.
local component_exts = { "hbs", "js", "ts", "gjs", "gts" }

-- Full symbol under the cursor plus the character preceding it. Includes Ember
-- path chars (:: / -) that <cword> would split on; the preceding char lets us
-- detect angle-bracket (<Foo) component invocations.
local function token_at_cursor()
	local line = vim.api.nvim_get_current_line()
	if line == "" then
		return "", ""
	end
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1
	local is_tok = function(c)
		return c ~= "" and c:match("[%w:@/_%-]") ~= nil
	end
	if not is_tok(line:sub(col, col)) then
		if col > 1 and is_tok(line:sub(col - 1, col - 1)) then
			col = col - 1
		else
			return "", ""
		end
	end
	local s = col
	while s > 1 and is_tok(line:sub(s - 1, s - 1)) do
		s = s - 1
	end
	local e = col
	while e < #line and is_tok(line:sub(e + 1, e + 1)) do
		e = e + 1
	end
	return line:sub(s, e), line:sub(s - 1, s - 1)
end

local function dasherize(s)
	s = s:gsub("(%u+)(%u%l)", "%1-%2")
	s = s:gsub("(%l)(%u)", "%1-%2")
	return s:lower()
end

-- Ancestor app/components (and addon/components) dirs above the current file.
local function components_roots()
	local roots = {}
	local dir = vim.fn.expand("%:p:h")
	while dir and dir ~= "" do
		for _, sub in ipairs({ "app/components", "addon/components" }) do
			local cand = dir .. "/" .. sub
			if vim.fn.isdirectory(cand) == 1 then
				table.insert(roots, cand)
			end
		end
		local parent = vim.fn.fnamemodify(dir, ":h")
		if parent == dir then
			break
		end
		dir = parent
	end
	return roots
end

-- Component reference under the cursor -> component path, or nil if it isn't one.
local function component_path(token, prev)
	if token == "" or token:sub(1, 1) == "@" then
		return nil
	end
	if token:match("^%u") and (token:find("::") or prev == "<") then
		-- PascalCase invocation: ConversionTracking::Header -> conversion-tracking/header,
		-- CampaignDetailsModuleHeader -> campaign-details-module-header.
		local segs = {}
		for seg in token:gmatch("[^:]+") do
			if seg ~= "" then
				table.insert(segs, dasherize(seg))
			end
		end
		return table.concat(segs, "/")
	elseif token:find("/") and token:match("^%l") then
		-- Curly path invocation: {{conversion-tracking/header}}.
		return token
	end
	return nil
end

-- Resolve the Ember component under the cursor. Returns the backing files (may
-- be empty) and the component token (for the tag stack / picker title).
function M.resolve_component()
	local token, prev = token_at_cursor()
	local path = component_path(token, prev)
	if not path then
		return {}, token
	end
	local files, seen = {}, {}
	for _, root in ipairs(components_roots()) do
		for _, ext in ipairs(component_exts) do
			for _, base in ipairs({ root .. "/" .. path, root .. "/" .. path .. "/index" }) do
				local f = base .. "." .. ext
				if file_exists(f) and not seen[f] then
					seen[f] = true
					table.insert(files, f)
				end
			end
		end
	end
	return files, token
end

return M
