local M = {}

-- Helper functions for file operations
local function open_file(file_path) vim.cmd("edit " .. vim.fn.fnameescape(file_path)) end

local function file_exists(file_path) return vim.fn.filereadable(file_path) == 1 end

local function try_open_file(file_path, error_message)
  if file_exists(file_path) then
    open_file(file_path)
    return true
  end
  if error_message then vim.notify(error_message, vim.log.levels.WARN) end
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
  local current_file = vim.fn.expand "%:p"

  if current_file:match "%.hbs$" then
    -- From .hbs -> try .js first, then .ts
    try_open_first_existing({
      current_file:gsub("%.hbs$", ".js"),
      current_file:gsub("%.hbs$", ".ts"),
    }, "No corresponding .js or .ts file found")
  elseif current_file:match "%.js$" then
    -- From .js -> .hbs
    try_open_file(current_file:gsub("%.js$", ".hbs"), "File not found: " .. current_file:gsub("%.js$", ".hbs"))
  elseif current_file:match "%.ts$" then
    -- From .ts -> .hbs
    try_open_file(current_file:gsub("%.ts$", ".hbs"), "File not found: " .. current_file:gsub("%.ts$", ".hbs"))
  else
    vim.notify("Not an Ember file (.hbs, .js, or .ts)", vim.log.levels.WARN)
  end
end

--- Open the test file for an Ember file (integration for components, unit for others)
function M.open_test()
  local current_file = vim.fn.expand "%:p"

  -- Try to match app/components/... for integration tests
  local component_path = current_file:match "app/components/(.+)%.[hj][bs]?s?$"
  if component_path then
    local project_root = current_file:match "(.+)/app/components/"
    local test_file = project_root .. "/tests/integration/components/" .. component_path .. "-test.js"
    try_open_file(test_file, "Test not found: " .. test_file)
    return
  end

  -- Try to match app/<type>/... for unit tests (e.g., app/utils/, app/services/, etc.)
  local app_path = current_file:match "app/(.+)%.[jt]s$"
  if app_path then
    local project_root = current_file:match "(.+)/app/"
    local test_file = project_root .. "/tests/unit/" .. app_path .. "-test.js"
    try_open_file(test_file, "Test not found: " .. test_file)
    return
  end

  vim.notify("Not in an Ember app file", vim.log.levels.WARN)
end

--- Open the source file from a test file
function M.open_source()
  local current_file = vim.fn.expand "%:p"

  -- Try to match integration component tests: tests/integration/components/<path>-test.[jt]s
  local integration_path = current_file:match "tests/integration/components/(.+)%-test%.[jt]s$"
  if integration_path then
    local project_root = current_file:match "(.+)/tests/integration/components/"
    -- Try .hbs first (template), then .js, then .ts
    try_open_first_existing({
      project_root .. "/app/components/" .. integration_path .. ".hbs",
      project_root .. "/app/components/" .. integration_path .. ".js",
      project_root .. "/app/components/" .. integration_path .. ".ts",
    }, "Source file not found for: " .. integration_path)
    return
  end

  -- Try to match unit tests: tests/unit/<category>/<path>-test.[jt]s
  local unit_category, unit_path = current_file:match "tests/unit/([^/]+)/(.+)%-test%.[jt]s$"
  if unit_category and unit_path then
    local project_root = current_file:match "(.+)/tests/unit/"
    -- Try .js first, then .ts
    try_open_first_existing({
      project_root .. "/app/" .. unit_category .. "/" .. unit_path .. ".js",
      project_root .. "/app/" .. unit_category .. "/" .. unit_path .. ".ts",
    }, "Source file not found: app/" .. unit_category .. "/" .. unit_path)
    return
  end

  vim.notify("Not in an Ember test file", vim.log.levels.WARN)
end

--- Copy Ember test module string to clipboard
--- Generates the module string from test file path and copies to system clipboard
--- Examples:
---   tests/integration/components/foo/bar-test.js -> 'Integration | Component | foo/bar'
---   tests/unit/services/my-service-test.js -> 'Unit | Service | my-service'
---   tests/acceptance/login-test.js -> 'Acceptance | login'
function M.copy_test_module()
  local current_file = vim.fn.expand "%:p"

  -- Category plural to singular mapping
  local category_map = {
    components = "Component",
    services = "Service",
    utils = "Util",
    helpers = "Helper",
    routes = "Route",
    controllers = "Controller",
  }

  -- Helper to normalize category name (plural to singular)
  local function normalize_category(category)
    return category_map[category] or category:sub(1, 1):upper() .. category:sub(2):lower()
  end

  -- Helper to copy and notify
  local function copy_module_string(parts)
    local module_string = table.concat(parts, " | ")
    vim.fn.setreg("+", module_string)
    vim.notify("Copied: " .. module_string, vim.log.levels.INFO)
  end

  -- Try to match acceptance tests: tests/acceptance/<path>-test.[jt]s
  local acceptance_path = current_file:match "tests/acceptance/(.+)%-test%.[jt]s$"
  if acceptance_path then
    copy_module_string { "Acceptance", acceptance_path }
    return
  end

  -- Try to match integration tests: tests/integration/<category>/<path>-test.[jt]s
  local integration_category, integration_path = current_file:match "tests/integration/([^/]+)/(.+)%-test%.[jt]s$"
  if integration_category and integration_path then
    copy_module_string { "Integration", normalize_category(integration_category), integration_path }
    return
  end

  -- Try to match unit tests: tests/unit/<category>/<path>-test.[jt]s
  local unit_category, unit_path = current_file:match "tests/unit/([^/]+)/(.+)%-test%.[jt]s$"
  if unit_category and unit_path then
    copy_module_string { "Unit", normalize_category(unit_category), unit_path }
    return
  end

  -- Not in a recognized test file
  vim.notify(
    "Not in an Ember test file (tests/acceptance/..., tests/integration/..., or tests/unit/...)",
    vim.log.levels.WARN
  )
end

-- Helper function to replace characters in t-def first quoted string only
-- This handles multiline t-def blocks and ignores doc="..." attributes
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
    if notify_msg then vim.notify(notify_msg, vim.log.levels.INFO) end
    return true
  end
  return false
end

-- convert unicode escapes to actual characters on load to prevent glimmer treesitter from breaking
-- Only affects the first quoted string in t-def, NOT doc="..." values
function M.convert_unicode_to_char(buf)
  -- Unicode escape -> character mappings
  local unicode_to_char = {
    ["\\u2019"] = "'", -- Right single quotation mark
    ["\\u201C"] = '"', -- Left double quotation mark
    ["\\u201c"] = '"', -- Left double quotation mark (lowercase)
    ["\\u201D"] = '"', -- Right double quotation mark
    ["\\u201d"] = '"', -- Right double quotation mark (lowercase)
    ["\\u0022"] = '"', -- Straight double quotation mark
    ["\\u0026"] = "&", -- Ampersand
  }
  replace_in_tdef(buf, unicode_to_char, "Replaced unicode escapes with actual characters")
end

-- convert characters back to unicode escapes on save to preserve original file content
-- Only affects the first quoted string in t-def, NOT doc="..." values
function M.convert_char_to_unicode(buf)
  -- Character -> unicode escape mappings (reverse)
  local char_to_unicode = { ["'"] = "\\u2019", ['"'] = "\\u0022", ["&"] = "\\u0026" }
  replace_in_tdef(buf, char_to_unicode, nil)
end

return M
