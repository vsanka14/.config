-- Java LSP lifecycle, DAP wiring, and hot-code replace via nvim-jdtls.
-- Ported from astrocommunity pack/java (https://github.com/AstroNvim/astrocommunity)
-- with workspace dirs, lombok agent, mason-managed jdtls/debug-adapter/test bundles.
return {
  "mfussenegger/nvim-jdtls",
  ft = "java",
  dependencies = { "mfussenegger/nvim-dap" },
  config = function()
    local mason_path = vim.fn.stdpath("data") .. "/mason"
    local jdtls_path = mason_path .. "/packages/jdtls"
    local lombok_path = jdtls_path .. "/lombok.jar"

    -- Find the launcher jar
    local launcher_jar = vim.fn.glob(jdtls_path .. "/plugins/org.eclipse.equinox.launcher_*.jar")

    -- Platform-specific config
    local config_dir
    if vim.fn.has("mac") == 1 then
      config_dir = jdtls_path .. "/config_mac"
    elseif vim.fn.has("unix") == 1 then
      config_dir = jdtls_path .. "/config_linux"
    else
      config_dir = jdtls_path .. "/config_win"
    end

    -- Workspace directory per project
    local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
    local workspace_dir = vim.fn.stdpath("data") .. "/site/java/workspace-root/" .. project_name

    -- DAP bundles
    local bundles = {}
    local debug_jar = vim.fn.glob(mason_path .. "/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar")
    if debug_jar ~= "" then
      table.insert(bundles, debug_jar)
    end
    local test_jars = vim.fn.glob(mason_path .. "/packages/java-test/extension/server/*.jar", false, true)
    for _, jar in ipairs(test_jars) do
      if not jar:match("com.microsoft.java.test.runner") then
        table.insert(bundles, jar)
      end
    end

    -- Root detection
    local root_dir = require("jdtls.setup").find_root({ ".git", "mvnw", "gradlew", "pom.xml", "build.gradle" })

    local config = {
      cmd = {
        "java",
        "-Declipse.application=org.eclipse.jdt.ls.core.id1",
        "-Dosgi.bundles.defaultStartLevel=4",
        "-Declipse.product=org.eclipse.jdt.ls.core.product",
        "-Dlog.protocol=true",
        "-Dlog.level=ALL",
        "-javaagent:" .. lombok_path,
        "-Xms1g",
        "--add-modules=ALL-SYSTEM",
        "--add-opens", "java.base/java.util=ALL-UNNAMED",
        "--add-opens", "java.base/java.lang=ALL-UNNAMED",
        "-jar", launcher_jar,
        "-configuration", config_dir,
        "-data", workspace_dir,
      },
      root_dir = root_dir,
      settings = {
        java = {
          eclipse = { downloadSources = true },
          maven = { downloadSources = true },
          configuration = { updateBuildConfiguration = "interactive" },
          codeGeneration = { toString = { template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}" } },
          implementationsCodeLens = { enabled = true },
          referencesCodeLens = { enabled = true },
          inlayHints = { parameterNames = { enabled = "all" } },
          signatureHelp = { enabled = true },
          completion = { favoriteStaticMembers = {
            "org.hamcrest.MatcherAssert.assertThat",
            "org.hamcrest.Matchers.*",
            "org.hamcrest.CoreMatchers.*",
            "org.junit.jupiter.api.Assertions.*",
            "java.util.Objects.requireNonNull",
            "java.util.Objects.requireNonNullElse",
            "org.mockito.Mockito.*",
          }},
          sources = { organizeImports = { starThreshold = 9999, staticStarThreshold = 9999 } },
        },
      },
      init_options = { bundles = bundles },
      on_attach = function(client, bufnr)
        -- Setup DAP
        pcall(function() require("jdtls").setup_dap({ hotcodereplace = "auto" }) end)
        pcall(function() require("jdtls.dap").setup_dap_main_class_configs() end)
      end,
    }

    -- Start jdtls on java filetype
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "java",
      callback = function()
        require("jdtls").start_or_attach(config)
      end,
      desc = "Start/attach nvim-jdtls",
    })

    -- Start immediately if we're already in a java buffer
    if vim.bo.filetype == "java" then
      require("jdtls").start_or_attach(config)
    end
  end,
}
