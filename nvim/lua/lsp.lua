-- Native Neovim 0.11 LSP configuration (no lspconfig plugin)

-- Diagnostics config
vim.diagnostic.config({
  virtual_text = true,
  underline = true,
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "\u{f0674}",
      [vim.diagnostic.severity.WARN]  = "\u{f0026}",
      [vim.diagnostic.severity.INFO]  = "\u{f02fc}",
      [vim.diagnostic.severity.HINT]  = "\u{f0835}",
    },
  },
  float = { border = "rounded" },
  severity_sort = true,
})

-- LSP server configurations
vim.lsp.config("lua_ls", {
  cmd = { "lua-language-server" },
  filetypes = { "lua" },
  root_markers = { ".luarc.json", ".luarc.jsonc", ".stylua.toml", "stylua.toml", ".git" },
  settings = {
    Lua = {
      format = { enable = false }, -- stylua handles formatting
      hint = { enable = true, arrayIndex = "Disable" },
      runtime = { version = "LuaJIT" },
      workspace = {
        checkThirdParty = false,
        library = { vim.env.VIMRUNTIME },
      },
      diagnostics = {
        globals = { "vim" },
      },
    },
  },
})

vim.lsp.config("vtsls", {
  cmd = { "vtsls", "--stdio" },
  filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
  root_markers = { "tsconfig.json", "package.json", ".git" },
  settings = {
    typescript = {
      tsserver = { maxTsServerMemory = 8192 },
      updateImportsOnFileMove = { enabled = "always" },
      inlayHints = {
        enumMemberValues = { enabled = true },
        functionLikeReturnTypes = { enabled = true },
        parameterNames = { enabled = "all" },
        parameterTypes = { enabled = true },
        propertyDeclarationTypes = { enabled = true },
        variableTypes = { enabled = true },
      },
    },
    javascript = {
      updateImportsOnFileMove = { enabled = "always" },
      inlayHints = {
        enumMemberValues = { enabled = true },
        functionLikeReturnTypes = { enabled = true },
        parameterNames = { enabled = "literals" },
        parameterTypes = { enabled = true },
        propertyDeclarationTypes = { enabled = true },
        variableTypes = { enabled = true },
      },
    },
    vtsls = {
      enableMoveToFileCodeAction = true,
    },
  },
})

vim.lsp.config("ember", {
  cmd = { "ember-language-server", "--stdio" },
  filetypes = { "handlebars" },
  root_markers = { "ember-cli-build.js", ".ember-cli" },
})

-- Enable all non-jdtls servers (jdtls is managed by nvim-jdtls plugin)
vim.lsp.enable({ "vtsls", "lua_ls", "ember" })

-- LspAttach keymaps and features
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("lsp_attach", { clear = true }),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    local bufnr = args.buf
    local map = function(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
    end

    -- Navigation
    map("n", "gd", vim.lsp.buf.definition, "Go to definition")
    map("n", "gD", vim.lsp.buf.declaration, "Go to declaration")
    map("n", "gr", vim.lsp.buf.references, "Go to references")
    map("n", "gi", vim.lsp.buf.implementation, "Go to implementation")
    map("n", "K", vim.lsp.buf.hover, "Hover documentation")
    map("n", "<C-k>", vim.lsp.buf.signature_help, "Signature help")

    -- Actions
    map("n", "<Leader>la", vim.lsp.buf.code_action, "Code action")
    map("v", "<Leader>la", vim.lsp.buf.code_action, "Code action")
    map("n", "<Leader>lr", vim.lsp.buf.rename, "Rename symbol")
    map("n", "<Leader>ld", vim.diagnostic.open_float, "Diagnostics float")
    map("n", "<Leader>lf", function() vim.lsp.buf.format({ async = true }) end, "Format buffer")

    -- Diagnostic navigation
    map("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end, "Next diagnostic")
    map("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, "Previous diagnostic")

    -- Codelens
    if client and client:supports_method("textDocument/codeLens") then
      vim.api.nvim_create_autocmd({ "InsertLeave", "BufEnter" }, {
        buffer = bufnr,
        callback = function()
          vim.lsp.codelens.refresh({ bufnr = bufnr })
        end,
        desc = "Refresh codelens",
      })
    end
  end,
})
