return {
  "mfussenegger/nvim-dap",
  config = function()
    local dap = require "dap"

    -- Remote JVM attach configuration for campaign-manager-api
    -- Start the app with: aves-tools run --debug -t
    dap.configurations.java = dap.configurations.java or {}
    table.insert(dap.configurations.java, {
      type = "java",
      request = "attach",
      name = "Attach to Remote JVM (port 9999)",
      hostName = "::1",
      port = 9999,
    })
  end,
}
