local M = {}

--- Switch between Ember .hbs and .js/.ts files
function M.go_to_alternate()
  local current_file = vim.fn.expand("%:p")
  local target_file

  if current_file:match("%.hbs$") then
    -- From .hbs -> try .js first, then .ts
    local js_file = current_file:gsub("%.hbs$", ".js")
    local ts_file = current_file:gsub("%.hbs$", ".ts")
    if vim.fn.filereadable(js_file) == 1 then
      target_file = js_file
    elseif vim.fn.filereadable(ts_file) == 1 then
      target_file = ts_file
    else
      vim.notify("No corresponding .js or .ts file found", vim.log.levels.WARN)
      return
    end
  elseif current_file:match("%.js$") then
    -- From .js -> .hbs
    target_file = current_file:gsub("%.js$", ".hbs")
  elseif current_file:match("%.ts$") then
    -- From .ts -> .hbs
    target_file = current_file:gsub("%.ts$", ".hbs")
  else
    vim.notify("Not an Ember file (.hbs, .js, or .ts)", vim.log.levels.WARN)
    return
  end

  if vim.fn.filereadable(target_file) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(target_file))
  else
    vim.notify("File not found: " .. target_file, vim.log.levels.WARN)
  end
end

--- Open the test file for an Ember file (integration for components, unit for others)
function M.open_test()
  local current_file = vim.fn.expand("%:p")

  -- Try to match app/components/... for integration tests
  local component_path = current_file:match("app/components/(.+)%.[hj][bs]?s?$")
  if component_path then
    local project_root = current_file:match("(.+)/app/components/")
    local test_file = project_root .. "/tests/integration/components/" .. component_path .. "-test.js"
    if vim.fn.filereadable(test_file) == 1 then
      vim.cmd("edit " .. vim.fn.fnameescape(test_file))
    else
      vim.notify("Test not found: " .. test_file, vim.log.levels.WARN)
    end
    return
  end

  -- Try to match app/<type>/... for unit tests (e.g., app/utils/, app/services/, etc.)
  local app_path = current_file:match("app/(.+)%.[jt]s$")
  if app_path then
    local project_root = current_file:match("(.+)/app/")
    local test_file = project_root .. "/tests/unit/" .. app_path .. "-test.js"
    if vim.fn.filereadable(test_file) == 1 then
      vim.cmd("edit " .. vim.fn.fnameescape(test_file))
    else
      vim.notify("Test not found: " .. test_file, vim.log.levels.WARN)
    end
    return
  end

  vim.notify("Not in an Ember app file", vim.log.levels.WARN)
end

return M
