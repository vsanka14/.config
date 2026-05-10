return {
	{
		"mfussenegger/nvim-dap",
		lazy = true,
		dependencies = { "rcarriga/nvim-dap-ui" },
		config = function()
			local dap = require("dap")

			dap.configurations.java = dap.configurations.java or {}
			table.insert(dap.configurations.java, {
				type = "java",
				request = "attach",
				name = "Attach to cm-api (port 9999)",
				hostName = "::1",
				port = 9999,
			})
		end,
	},
	{
		"rcarriga/nvim-dap-ui",
		lazy = true,
		dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
		config = function()
			local dapui = require("dapui")
			dapui.setup()

			local dap = require("dap")
			dap.listeners.after.event_initialized["dapui_config"] = function()
				dapui.open()
			end
			dap.listeners.before.event_terminated["dapui_config"] = function()
				dapui.close()
			end
			dap.listeners.before.event_exited["dapui_config"] = function()
				dapui.close()
			end
		end,
	},
}
