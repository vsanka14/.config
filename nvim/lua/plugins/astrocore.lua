-- AstroCore provides a central place to modify mappings, vim options, autocommands, and more!
-- Configuration documentation can be found with `:h astrocore`
-- NOTE: We highly recommend setting up the Lua Language Server (`:LspInstall lua_ls`)
--       as this provides autocomplete and documentation while editing

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    -- Configure core features of AstroNvim
    features = {
      large_buf = { size = 1024 * 256, lines = 10000 }, -- set global limits for large files for disabling features like treesitter
      autopairs = true, -- enable autopairs at start
      cmp = true, -- enable completion at start
      diagnostics = { virtual_text = true, virtual_lines = false }, -- diagnostic settings on startup
      highlighturl = true, -- highlight URLs at start
      notifications = true, -- enable notifications at start
    },
    -- Diagnostics configuration (for vim.diagnostics.config({...})) when diagnostics are on
    diagnostics = {
      virtual_text = true,
      underline = true,
    },
    -- passed to `vim.filetype.add`
    filetypes = {
      -- see `:h vim.filetype.add` for usage
      extension = {},
      filename = {},
      pattern = {},
    },
    -- vim options can be configured here
    options = {
      opt = { -- vim.opt.<key>
        relativenumber = true, -- sets vim.opt.relativenumber
        number = true, -- sets vim.opt.number
        spell = false, -- sets vim.opt.spell
        signcolumn = "yes", -- sets vim.opt.signcolumn to yes
        wrap = true, -- enable word wrap for better markdown editing
        linebreak = true, -- wrap at word boundaries
        textwidth = 0, -- disable auto line breaks
        wrapmargin = 0, -- disable wrap margin
      },
      g = { -- vim.g.<key>
        -- configure global vim variables (vim.g)
        -- NOTE: `mapleader` and `maplocalleader` must be set in the AstroNvim opts or before `lazy.setup`
        -- This can be found in the `lua/lazy_setup.lua` file
      },
    },
    -- Mappings can be configured through AstroCore as well.
    -- NOTE: keycodes follow the casing in the vimdocs. For example, `<Leader>` must be capitalized
    mappings = {
      -- first key is the mode
      i = {
        -- Insert mode mappings
        ["jk"] = { "<Esc>", desc = "Exit insert mode" },
      },
      n = {
        -- second key is the lefthand side of the map

        -- Redo with U (more intuitive than Ctrl+r)
        ["U"] = { "<C-r>", desc = "Redo" },

        -- navigate buffer tabs
        ["]b"] = { function() require("astrocore.buffer").nav(vim.v.count1) end, desc = "Next buffer" },
        ["[b"] = { function() require("astrocore.buffer").nav(-vim.v.count1) end, desc = "Previous buffer" },

        -- mappings seen under group name "Buffer"
        ["<Leader>bd"] = {
          function()
            require("astroui.status.heirline").buffer_picker(
              function(bufnr) require("astrocore.buffer").close(bufnr) end
            )
          end,
          desc = "Close buffer from tabline",
        },

        -- tables with just a `desc` key will be registered with which-key if it's installed
        -- this is useful for naming menus
        -- ["<Leader>b"] = { desc = "Buffers" },

        -- setting a mapping to false will disable it
        -- ["<C-S>"] = false,

        -- OpenCode AI assistant keymaps
        ["<Leader>a"] = { desc = "AI (OpenCode)" },
        ["<Leader>aa"] = {
          function() require("opencode").ask("@this: ", { submit = true }) end,
          desc = "Ask OpenCode about selection/cursor",
        },
        ["<Leader>aA"] = {
          function() require("opencode").ask() end,
          desc = "Ask OpenCode (empty prompt)",
        },
        ["<Leader>as"] = {
          function() require("opencode").select() end,
          desc = "Select OpenCode action",
        },
        ["<Leader>at"] = {
          function() require("opencode").toggle() end,
          desc = "Toggle OpenCode terminal",
        },
        ["<Leader>ae"] = {
          function() require("opencode").prompt("Explain @this and its context", { submit = true }) end,
          desc = "Explain code",
        },
        ["<Leader>ar"] = {
          function() require("opencode").prompt("Review @this for correctness and readability", { submit = true }) end,
          desc = "Review code",
        },
        ["<Leader>af"] = {
          function() require("opencode").prompt("Fix @diagnostics", { submit = true }) end,
          desc = "Fix diagnostics",
        },
        ["<Leader>ad"] = {
          function() require("opencode").prompt("Add comments documenting @this", { submit = true }) end,
          desc = "Document code",
        },
        ["<Leader>ao"] = {
          function() require("opencode").prompt("Optimize @this for performance and readability", { submit = true }) end,
          desc = "Optimize code",
        },
        ["<Leader>ai"] = {
          function() require("opencode").prompt("Implement @this", { submit = true }) end,
          desc = "Implement (from comment/signature)",
        },
        ["<Leader>aT"] = {
          function() require("opencode").prompt("Add tests for @this", { submit = true }) end,
          desc = "Add tests",
        },
        ["<Leader>ag"] = {
          function() require("opencode").prompt("Review the following git diff for correctness and readability: @diff", { submit = true }) end,
          desc = "Review git diff",
        },

        -- GitLens-like functionality keymaps
        ["<Leader>g"] = { desc = "Git" },
        ["<Leader>gb"] = { "<cmd>GitBlameToggle<cr>", desc = "Toggle Git Blame" },
        ["<Leader>gB"] = { function() require("gitsigns").blame_line { full = true } end, desc = "Git Blame Line" },
        ["<Leader>gd"] = { "<cmd>DiffviewOpen<cr>", desc = "Open Diff View" },
        ["<Leader>gh"] = { "<cmd>DiffviewFileHistory %<cr>", desc = "File History" },
        ["<Leader>gH"] = { "<cmd>DiffviewFileHistory<cr>", desc = "Project History" },
        ["<Leader>gg"] = { function() Snacks.lazygit() end, desc = "Open Lazygit" },
        ["<Leader>gp"] = { function() require("gitsigns").preview_hunk() end, desc = "Preview Hunk" },
        ["<Leader>gr"] = { function() require("gitsigns").reset_hunk() end, desc = "Reset Hunk" },
        ["<Leader>gR"] = { function() require("gitsigns").reset_buffer() end, desc = "Reset Buffer" },
        ["<Leader>gs"] = { function() require("gitsigns").stage_hunk() end, desc = "Stage Hunk" },
        ["<Leader>gS"] = { function() require("gitsigns").stage_buffer() end, desc = "Stage Buffer" },
        ["<Leader>gu"] = { function() require("gitsigns").reset_hunk() end, desc = "Undo Stage Hunk" },
        ["]h"] = { function() require("gitsigns").nav_hunk "next" end, desc = "Next Git Hunk" },
        ["[h"] = { function() require("gitsigns").nav_hunk "prev" end, desc = "Previous Git Hunk" },

        -- Screenkey toggle
        ["<Leader>uK"] = { "<cmd>Screenkey<cr>", desc = "Toggle Screenkey" },
      },
      v = {
        -- Visual mode git operations
        ["<Leader>gs"] = {
          function() require("gitsigns").stage_hunk { vim.fn.line ".", vim.fn.line "v" } end,
          desc = "Stage Selected Hunk",
        },
        ["<Leader>gr"] = {
          function() require("gitsigns").reset_hunk { vim.fn.line ".", vim.fn.line "v" } end,
          desc = "Reset Selected Hunk",
        },
        -- Visual mode OpenCode operations (work on selection)
        ["<Leader>a"] = { desc = "AI (OpenCode)" },
        ["<Leader>aa"] = {
          function() require("opencode").ask("@this: ", { submit = true }) end,
          desc = "Ask OpenCode about selection",
        },
        ["<Leader>ae"] = {
          function() require("opencode").prompt("Explain @this and its context", { submit = true }) end,
          desc = "Explain selection",
        },
        ["<Leader>ar"] = {
          function() require("opencode").prompt("Review @this for correctness and readability", { submit = true }) end,
          desc = "Review selection",
        },
        ["<Leader>ad"] = {
          function() require("opencode").prompt("Add comments documenting @this", { submit = true }) end,
          desc = "Document selection",
        },
        ["<Leader>ao"] = {
          function() require("opencode").prompt("Optimize @this for performance and readability", { submit = true }) end,
          desc = "Optimize selection",
        },
        ["<Leader>aT"] = {
          function() require("opencode").prompt("Add tests for @this", { submit = true }) end,
          desc = "Add tests for selection",
        },
      },
    },
    -- Add autocmds for better markdown editing
    autocmds = {
      markdown_settings = {
        {
          event = "FileType",
          pattern = "markdown",
          callback = function()
            vim.opt_local.wrap = true
            vim.opt_local.linebreak = true
            vim.opt_local.conceallevel = 2
            vim.opt_local.concealcursor = "nc"
          end,
          desc = "Set markdown-specific options for better editing",
        },
      },
    },
  },
}
