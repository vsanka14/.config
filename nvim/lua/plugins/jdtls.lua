-- Java LSP lifecycle, DAP wiring, and hot-code replace via nvim-jdtls.
-- Ported from astrocommunity pack/java (https://github.com/AstroNvim/astrocommunity)
-- Uses $MASON/share/ symlinks for stable paths across mason package updates.
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

    local function start_jdtls()
      local root_dir = vim.fs.root(0, { ".git", "mvnw", "gradlew" })
      if not root_dir or root_dir == "" then return end

      local project_name = vim.fn.fnamemodify(root_dir, ":t")
      local workspace_dir = vim.fn.stdpath("data") .. "/site/java/workspace-root/" .. project_name
      vim.fn.mkdir(workspace_dir, "p")

      require("jdtls").start_or_attach({
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
          "--add-opens", "java.base/java.util=ALL-UNNAMED",
          "--add-opens", "java.base/java.lang=ALL-UNNAMED",
          "-jar", vim.fn.expand("$MASON/share/jdtls/plugins/org.eclipse.equinox.launcher.jar"),
          "-configuration", vim.fn.expand("$MASON/share/jdtls/config"),
          "-data", workspace_dir,
        },
        root_dir = root_dir,
        settings = {
          java = {
            eclipse = { downloadSources = true },
            configuration = { updateBuildConfiguration = "interactive" },
            maven = { downloadSources = true },
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
        filetypes = { "java" },
        on_attach = function(client, bufnr)
          require("jdtls").setup_dap({ hotcodereplace = "auto" })
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

    -- Start immediately if we're already in a java buffer
    if vim.bo.filetype == "java" then
      start_jdtls()
    end
  end,
}
