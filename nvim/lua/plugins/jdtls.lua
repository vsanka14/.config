-- Java LSP lifecycle, DAP wiring, and hot-code replace via nvim-jdtls.
-- Ported from astrocommunity pack/java (https://github.com/AstroNvim/astrocommunity)
-- Uses $MASON/share/ symlinks for stable paths across mason package updates.
--
-- LinkedIn MP support: detects multi-module Gradle projects, configures Buildship
-- import with proper memory/JVM settings, and registers generated source directories
-- (mainGeneratedDataTemplate, mainGeneratedRest, etc.) so PDL-generated classes resolve.
return {
	"mfussenegger/nvim-jdtls",
	ft = "java",
	dependencies = { "mfussenegger/nvim-dap" },
	config = function()
		-- DAP bundles (use $MASON/share/ symlinks, same as astrocommunity)
		local bundles = {
			vim.fn.expand("$MASON/share/java-debug-adapter/com.microsoft.java.debug.plugin.jar"),
		}
		local test_jars = vim.split(vim.fn.glob("$MASON/share/java-test/*.jar", true), "\n", {})
		for _, jar in ipairs(test_jars) do
			if jar ~= "" then
				table.insert(bundles, jar)
			end
		end

		-- JDK paths for runtime configuration
		local jdk_runtimes = {}
		local jdk_base = "/Library/Java/JavaVirtualMachines"
		local runtime_map = {
			["JavaSE-21"] = "jdk21.0.6-msft.jdk",
			["JavaSE-17"] = "jdk17.0.5-msft.jdk",
			["JavaSE-11"] = "jdk11.0.21-2-msft.jdk",
			["JavaSE-1.8"] = "jdk1.8.0_282-msft.jdk",
		}
		for name, dir in pairs(runtime_map) do
			local path = jdk_base .. "/" .. dir .. "/Contents/Home"
			if vim.fn.isdirectory(path) == 1 then
				table.insert(jdk_runtimes, {
					name = name,
					path = path,
					default = (name == "JavaSE-21"),
				})
			end
		end

		local function start_jdtls()
			-- Root detection: prefer settings.gradle / product-spec.json for LinkedIn MPs
			local root_dir = vim.fs.root(0, { "settings.gradle", "product-spec.json", "mvnw", "gradlew", ".git" })
			if not root_dir or root_dir == "" then
				return
			end

			local project_name = vim.fn.fnamemodify(root_dir, ":t")
			local workspace_dir = vim.fn.stdpath("data") .. "/site/java/workspace-root/" .. project_name
			vim.fn.mkdir(workspace_dir, "p")

			-- Detect if this is a Gradle project
			local is_gradle = vim.fn.filereadable(root_dir .. "/settings.gradle") == 1
				or vim.fn.filereadable(root_dir .. "/build.gradle") == 1

			-- Build extra classpath entries from build output (fallback for missing generated sources)
			local extra_classpaths = {}
			if is_gradle then
				local build_classes = vim.fn.glob(root_dir .. "/build/*/classes/java/mainGeneratedDataTemplate", true)
				for _, dir in ipairs(vim.split(build_classes, "\n", {})) do
					if dir ~= "" and vim.fn.isdirectory(dir) == 1 then
						table.insert(extra_classpaths, dir)
					end
				end
			end

			local jdtls = require("jdtls")

			jdtls.start_or_attach({
				cmd = {
					"java",
					"-Declipse.application=org.eclipse.jdt.ls.core.id1",
					"-Dosgi.bundles.defaultStartLevel=4",
					"-Declipse.product=org.eclipse.jdt.ls.core.product",
					"-Dlog.protocol=true",
					"-Dlog.level=ALL",
					"-javaagent:" .. vim.fn.expand("$MASON/share/jdtls/lombok.jar"),
					"-Xms2g",
					"-Xmx8g",
					"--add-modules=ALL-SYSTEM",
					"--add-opens",
					"java.base/java.util=ALL-UNNAMED",
					"--add-opens",
					"java.base/java.lang=ALL-UNNAMED",
					"-jar",
					vim.fn.expand("$MASON/share/jdtls/plugins/org.eclipse.equinox.launcher.jar"),
					"-configuration",
					vim.fn.expand("$MASON/share/jdtls/config"),
					"-data",
					workspace_dir,
				},
				root_dir = root_dir,
				settings = {
					java = {
						eclipse = { downloadSources = true },
						maven = { downloadSources = true },
						implementationsCodeLens = { enabled = true },
						referencesCodeLens = { enabled = true },
						inlayHints = { parameterNames = { enabled = "all" } },
						signatureHelp = { enabled = true },
						completion = {
							favoriteStaticMembers = {
								"org.hamcrest.MatcherAssert.assertThat",
								"org.hamcrest.Matchers.*",
								"org.hamcrest.CoreMatchers.*",
								"org.junit.jupiter.api.Assertions.*",
								"java.util.Objects.requireNonNull",
								"java.util.Objects.requireNonNullElse",
								"org.mockito.Mockito.*",
							},
						},
						sources = { organizeImports = { starThreshold = 9999, staticStarThreshold = 9999 } },
						-- Gradle import configuration (critical for LinkedIn multi-module MPs)
						import = {
							gradle = {
								enabled = is_gradle,
								wrapper = { enabled = true },
								annotationProcessing = { enabled = true },
								-- Match the project's gradle.properties JVM args for import
								jvmArguments = "-Xmx12G --add-opens java.base/java.util=ALL-UNNAMED --add-opens java.base/java.lang=ALL-UNNAMED",
							},
						},
						-- Java runtime configuration: jdtls uses JDK 21 but projects may target 11/17
						configuration = {
							updateBuildConfiguration = "interactive",
							runtimes = jdk_runtimes,
						},
						-- Extra classpath entries for build output dirs (PDL-generated .class files)
						project = {
							referencedLibraries = extra_classpaths,
						},
					},
				},
				init_options = {
					bundles = bundles,
					extendedClientCapabilities = jdtls.extendedClientCapabilities,
				},
				filetypes = { "java" },
				on_attach = function(client, bufnr)
					jdtls.setup_dap({ hotcodereplace = "auto" })
				end,
			})
		end

		-- Start jdtls on java filetype
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "java",
			callback = start_jdtls,
			desc = "Start/attach nvim-jdtls",
		})

		-- Load DAP main class configs after LSP attaches
		vim.api.nvim_create_autocmd("LspAttach", {
			pattern = "*.java",
			callback = function(args)
				local client = vim.lsp.get_client_by_id(args.data.client_id)
				if client and client.name == "jdtls" then
					require("jdtls.dap").setup_dap_main_class_configs()
				end
			end,
		})

		-- :JdtlsCleanWorkspace — nuke workspace data and restart (fixes corrupted indexes)
		vim.api.nvim_create_user_command("JdtlsCleanWorkspace", function()
			local root_dir = vim.fs.root(0, { "settings.gradle", "product-spec.json", "mvnw", "gradlew", ".git" })
			if not root_dir then
				vim.notify("No project root found", vim.log.levels.WARN)
				return
			end
			local project_name = vim.fn.fnamemodify(root_dir, ":t")
			local workspace = vim.fn.stdpath("data") .. "/site/java/workspace-root/" .. project_name

			-- Stop all jdtls clients first
			for _, client in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do
				client:stop()
			end
			vim.wait(1000, function()
				return #vim.lsp.get_clients({ name = "jdtls" }) == 0
			end)

			vim.fn.delete(workspace, "rf")
			vim.notify(
				"Cleaned workspace: " .. project_name .. "\nReopen a java file to reimport.",
				vim.log.levels.INFO
			)
		end, { desc = "Delete jdtls workspace data and stop server" })

		-- Start immediately if we're already in a java buffer
		if vim.bo.filetype == "java" then
			start_jdtls()
		end
	end,
}
