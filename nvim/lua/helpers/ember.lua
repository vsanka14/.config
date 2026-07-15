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

--- Open the test file for an Ember file (integration for components, unit for others)
function M.open_test()
	local current_file = vim.fn.expand("%:p")

	local component_path = current_file:match("app/components/(.+)%.[hj][bs]?s?$")
	if component_path then
		local project_root = current_file:match("(.+)/app/components/")
		local test_file = project_root .. "/tests/integration/components/" .. component_path .. "-test.js"
		try_open_file(test_file, "Test not found: " .. test_file)
		return
	end

	local app_path = current_file:match("app/(.+)%.[jt]s$")
	if app_path then
		local project_root = current_file:match("(.+)/app/")
		local test_file = project_root .. "/tests/unit/" .. app_path .. "-test.js"
		try_open_file(test_file, "Test not found: " .. test_file)
		return
	end

	vim.notify("Not in an Ember app file", vim.log.levels.WARN)
end

--- Open the source file from a test file
function M.open_source()
	local current_file = vim.fn.expand("%:p")

	local integration_path = current_file:match("tests/integration/components/(.+)%-test%.[jt]s$")
	if integration_path then
		local project_root = current_file:match("(.+)/tests/integration/components/")
		try_open_first_existing({
			project_root .. "/app/components/" .. integration_path .. ".hbs",
			project_root .. "/app/components/" .. integration_path .. ".js",
			project_root .. "/app/components/" .. integration_path .. ".ts",
		}, "Source file not found for: " .. integration_path)
		return
	end

	local unit_category, unit_path = current_file:match("tests/unit/([^/]+)/(.+)%-test%.[jt]s$")
	if unit_category and unit_path then
		local project_root = current_file:match("(.+)/tests/unit/")
		try_open_first_existing({
			project_root .. "/app/" .. unit_category .. "/" .. unit_path .. ".js",
			project_root .. "/app/" .. unit_category .. "/" .. unit_path .. ".ts",
		}, "Source file not found: app/" .. unit_category .. "/" .. unit_path)
		return
	end

	vim.notify("Not in an Ember test file", vim.log.levels.WARN)
end

--- Copy Ember test module string to clipboard
function M.copy_test_module()
	local current_file = vim.fn.expand("%:p")

	local category_map = {
		components = "Component",
		services = "Service",
		utils = "Util",
		helpers = "Helper",
		routes = "Route",
		controllers = "Controller",
	}

	local function normalize_category(category)
		return category_map[category] or category:sub(1, 1):upper() .. category:sub(2):lower()
	end

	local function copy_module_string(parts)
		local module_string = table.concat(parts, " | ")
		vim.fn.setreg("+", module_string)
		vim.notify("Copied: " .. module_string, vim.log.levels.INFO)
	end

	local acceptance_path = current_file:match("tests/acceptance/(.+)%-test%.[jt]s$")
	if acceptance_path then
		copy_module_string({ "Acceptance", acceptance_path })
		return
	end

	local integration_category, integration_path = current_file:match("tests/integration/([^/]+)/(.+)%-test%.[jt]s$")
	if integration_category and integration_path then
		copy_module_string({ "Integration", normalize_category(integration_category), integration_path })
		return
	end

	local unit_category, unit_path = current_file:match("tests/unit/([^/]+)/(.+)%-test%.[jt]s$")
	if unit_category and unit_path then
		copy_module_string({ "Unit", normalize_category(unit_category), unit_path })
		return
	end

	vim.notify(
		"Not in an Ember test file (tests/acceptance/..., tests/integration/..., or tests/unit/...)",
		vim.log.levels.WARN
	)
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

return M
