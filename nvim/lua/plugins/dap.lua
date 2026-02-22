return {
	{
		"mfussenegger/nvim-dap",
		lazy = true,
		config = function()
			local dap = require("dap")

			-- Java remote attach configs
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
				return 9999
			end

			local port = get_debug_port()
			dap.configurations.java = dap.configurations.java or {}
			table.insert(dap.configurations.java, {
				type = "java",
				request = "attach",
				name = string.format("Attach to Remote JVM (port %d)", port),
				hostName = "::1",
				port = port,
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
