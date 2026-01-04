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
        -- Insert mode mappings (better-escape.nvim handles jk/jj escape)
      },
      n = {
        -- second key is the lefthand side of the map

        -- Redo with U (more intuitive than Ctrl+r)
        ["U"] = { "<C-r>", desc = "Redo" },

        -- navigate buffer tabs
        ["<Leader>bn"] = { function() require("astrocore.buffer").nav(vim.v.count1) end, desc = "Next buffer" },
        ["<Leader>bp"] = { function() require("astrocore.buffer").nav(-vim.v.count1) end, desc = "Previous buffer" },

        -- mappings seen under group name "Buffer"
        ["<Leader>bb"] = {
          function()
            require("astroui.status.heirline").buffer_picker(function(bufnr) vim.api.nvim_set_current_buf(bufnr) end)
          end,
          desc = "Pick buffer from tabline",
        },
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
          function()
            require("opencode").prompt(
              "Review the following git diff for correctness and readability: @diff",
              { submit = true }
            )
          end,
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

        -- Markdown preview keymaps
        ["<Leader>m"] = { desc = "Markdown" },
        ["<Leader>mb"] = { "<cmd>MarkdownPreview<cr>", desc = "Browser Preview" },
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
      -- Auto-refresh Neo-tree git status when Neovim regains focus
      neotree_git_refresh = {
        {
          event = { "FocusGained", "BufEnter", "CursorHold" },
          pattern = "*",
          callback = function()
            if package.loaded["neo-tree.sources.manager"] then
              require("neo-tree.sources.manager").refresh "filesystem"
            end
          end,
          desc = "Refresh Neo-tree git status on focus",
        },
      },
      -- Markdown-specific settings
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
      -- OpenCode: Track files edited by OpenCode
      opencode_file_edited = {
        {
          event = "User",
          pattern = "OpencodeEvent:file.edited",
          callback = function(args)
            -- Initialize storage if needed
            _G.opencode_edited_files = _G.opencode_edited_files or {}
            local event = args.data and args.data.event
            if event and event.properties then
              local filepath = event.properties.file or event.properties.path
              if filepath then
                filepath = vim.fn.fnamemodify(filepath, ":p")
                _G.opencode_edited_files[filepath] = {
                  time = os.time(),
                  session_port = args.data.port,
                }
              end
            end
          end,
          desc = "Track files edited by OpenCode",
        },
      },
      -- OpenCode: Show notification when opening an OpenCode-edited file
      opencode_buf_enter = {
        {
          event = "BufEnter",
          callback = function(args)
            _G.opencode_edited_files = _G.opencode_edited_files or {}
            local filepath = vim.api.nvim_buf_get_name(args.buf)
            if filepath == "" then return end

            filepath = vim.fn.fnamemodify(filepath, ":p")
            local edit_info = _G.opencode_edited_files[filepath]

            if edit_info then
              local seconds_ago = os.time() - edit_info.time
              local time_str
              if seconds_ago < 60 then
                time_str = seconds_ago .. " seconds ago"
              elseif seconds_ago < 3600 then
                time_str = math.floor(seconds_ago / 60) .. " minutes ago"
              else
                time_str = math.floor(seconds_ago / 3600) .. " hours ago"
              end

              vim.notify(
                "This file was modified by OpenCode " .. time_str,
                vim.log.levels.INFO,
                { title = "OpenCode", timeout = 3000 }
              )

              vim.fn.sign_define("OpenCodeEdited", { text = "", texthl = "DiagnosticInfo" })
              vim.fn.sign_place(0, "opencode_signs", "OpenCodeEdited", args.buf, { lnum = 1, priority = 10 })
            end
          end,
          desc = "Notify when opening OpenCode-edited files",
        },
      },
      -- OpenCode: Clear tracking for a file when saved
      opencode_buf_write = {
        {
          event = "BufWritePost",
          callback = function(args)
            _G.opencode_edited_files = _G.opencode_edited_files or {}
            local filepath = vim.api.nvim_buf_get_name(args.buf)
            if filepath == "" then return end

            filepath = vim.fn.fnamemodify(filepath, ":p")
            if _G.opencode_edited_files[filepath] then
              _G.opencode_edited_files[filepath] = nil
              vim.fn.sign_unplace("opencode_signs", { buffer = args.buf })
              vim.notify("OpenCode change marker cleared", vim.log.levels.INFO, { title = "OpenCode", timeout = 2000 })
            end
          end,
          desc = "Clear OpenCode tracking on save",
        },
      },
      -- OpenCode: Track session status changes
      opencode_session_idle = {
        {
          event = "User",
          pattern = "OpencodeEvent:session.idle",
          callback = function()
            _G.opencode_edited_files = _G.opencode_edited_files or {}
            local count = vim.tbl_count(_G.opencode_edited_files)
            if count > 0 then
              vim.notify(
                "OpenCode finished. " .. count .. " file(s) were modified.",
                vim.log.levels.INFO,
                { title = "OpenCode" }
              )
            end
          end,
          desc = "Notify when OpenCode session becomes idle",
        },
      },
    },
    -- User commands
    commands = {
      -- List all OpenCode-edited files
      OpencodeEdits = {
        function()
          _G.opencode_edited_files = _G.opencode_edited_files or {}
          local files = {}
          for filepath, info in pairs(_G.opencode_edited_files) do
            local seconds_ago = os.time() - info.time
            local time_str
            if seconds_ago < 60 then
              time_str = seconds_ago .. "s ago"
            elseif seconds_ago < 3600 then
              time_str = math.floor(seconds_ago / 60) .. "m ago"
            else
              time_str = math.floor(seconds_ago / 3600) .. "h ago"
            end
            table.insert(files, { filepath = filepath, time_str = time_str, time = info.time })
          end

          if #files == 0 then
            vim.notify(
              "No files have been edited by OpenCode in this session",
              vim.log.levels.INFO,
              { title = "OpenCode" }
            )
            return
          end

          table.sort(files, function(a, b) return a.time > b.time end)

          vim.ui.select(files, {
            prompt = "OpenCode edited files:",
            format_item = function(item) return item.time_str .. " - " .. vim.fn.fnamemodify(item.filepath, ":~:.") end,
          }, function(choice)
            if choice then vim.cmd("edit " .. vim.fn.fnameescape(choice.filepath)) end
          end)
        end,
        desc = "List files edited by OpenCode",
      },
      -- Clear all OpenCode edit tracking
      OpencodeClearEdits = {
        function()
          _G.opencode_edited_files = _G.opencode_edited_files or {}
          local count = vim.tbl_count(_G.opencode_edited_files)
          _G.opencode_edited_files = {}
          vim.fn.sign_unplace "opencode_signs"
          vim.notify("Cleared " .. count .. " OpenCode edit marker(s)", vim.log.levels.INFO, { title = "OpenCode" })
        end,
        desc = "Clear all OpenCode edit tracking",
      },
    },
  },
}
