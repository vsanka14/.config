return {
  "mfussenegger/nvim-dap",
  config = function()
    local dap = require "dap"

    local function get_debug_port()
      local cwd = vim.fn.getcwd()
      local port_map = {
        ["campaign%-manager%-api"] = 9999,
        ["tscp%-assets"] = 23456,
      }

      for project, port in pairs(port_map) do
        if cwd:match(project) then
          return port
        end
      end

      return 9999 -- default
    end

    local port = get_debug_port()

    -- Remote JVM attach configuration
    -- Start the app with: aves-tools run --debug -t
    dap.configurations.java = dap.configurations.java or {}
    table.insert(dap.configurations.java, {
      type = "java",
      request = "attach",
      name = string.format("Attach to Remote JVM (port %d)", port),
      hostName = "::1",
      port = port,
    })
  end,
}
