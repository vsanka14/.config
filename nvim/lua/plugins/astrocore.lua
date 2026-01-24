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

        -- Centered scrolling
        ["<C-d>"] = { "<C-d>zz", desc = "Scroll down (centered)" },
        ["<C-u>"] = { "<C-u>zz", desc = "Scroll up (centered)" },
        ["<C-f>"] = { "<C-f>zz", desc = "Page down (centered)" },
        ["<C-b>"] = { "<C-b>zz", desc = "Page up (centered)" },

        -- Git functionality keymaps
        ["<Leader>g"] = { desc = "Git" },
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
      },
    },
    -- Add autocmds for better markdown editing
    autocmds = {
      -- Glimmer treesitter breaks on certain unicode characters in Ember.js .hbs files
      --  This set of autocmds will convert those unicode escapes to actual characters on buffer load,
      --  then convert them back to unicode escapes on save to preserve original file content.
      glimmer_unicode_fix = {
        -- Helper function to replace characters in t-def first quoted string only
        -- This handles multiline t-def blocks and ignores doc="..." attributes
        _replace_in_tdef = function(bufnr, char_map, notify_msg)
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          local content = table.concat(lines, "\n")

          local new_content = content:gsub('({{t%-def%s+")(.-)(")', function(prefix, str_content, suffix)
            local replaced_content = str_content
            for from, to in pairs(char_map) do
              replaced_content = replaced_content:gsub(from, to)
            end
            return prefix .. replaced_content .. suffix
          end)

          if new_content ~= content then
            local new_lines = vim.split(new_content, "\n", { plain = true })
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
            if notify_msg then vim.notify(notify_msg, vim.log.levels.INFO) end
            return true
          end
          return false
        end,

        -- Unicode escape -> character mappings
        _unicode_to_char = {
          ["\\u2019"] = "'", -- Right single quotation mark
          ["\\u201C"] = '"', -- Left double quotation mark
          ["\\u201c"] = '"', -- Left double quotation mark (lowercase)
          ["\\u201D"] = '"', -- Right double quotation mark
          ["\\u201d"] = '"', -- Right double quotation mark (lowercase)
          ["\\u0022"] = '"', -- Straight double quotation mark
          ["\\u0026"] = "&", -- Ampersand
        },

        -- Character -> unicode escape mappings (reverse)
        _char_to_unicode = { ["'"] = "\\u2019", ['"'] = "\\u0022", ["&"] = "\\u0026" },

        -- Read: convert unicode escapes to actual characters on load to prevent glimmer treesitter from breaking
        -- Only affects the first quoted string in t-def, NOT doc="..." values
        {
          event = { "BufReadPost", "BufNewFile" },
          pattern = { "*.hbs" },
          callback = function(args)
            local autocmds = require("astrocore").config.autocmds.glimmer_unicode_fix
            autocmds._replace_in_tdef(
              args.buf,
              autocmds._unicode_to_char,
              "Replaced unicode escapes with actual characters"
            )
          end,
        },
        -- Write: convert characters back to unicode escapes on save to preserve original file content
        -- Only affects the first quoted string in t-def, NOT doc="..." values
        {
          event = "BufWritePre",
          pattern = { "*.hbs" },
          callback = function(args)
            local autocmds = require("astrocore").config.autocmds.glimmer_unicode_fix
            autocmds._replace_in_tdef(args.buf, autocmds._char_to_unicode, nil)
          end,
        },
        -- Post-write: restore buffer to treesitter-friendly state (unicode escapes -> actual chars)
        -- This runs after the file is saved, so the file on disk has unicode escapes,
        -- but the buffer displays actual characters for proper treesitter highlighting
        {
          event = "BufWritePost",
          pattern = { "*.hbs" },
          callback = function(args)
            local autocmds = require("astrocore").config.autocmds.glimmer_unicode_fix
            autocmds._replace_in_tdef(
              args.buf,
              autocmds._unicode_to_char,
              "Restored unicode escapes to actual characters"
            )
          end,
        },
      },
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
      -- Auto refresh buffer when file changes on disk (triggers on focus gain, buffer enter)
      auto_refresh_buffer = {
        {
          event = { "FocusGained", "BufEnter" },
          pattern = "*",
          callback = function()
            if vim.o.autoread then vim.cmd.checktime() end
          end,
          desc = "Auto refresh buffer if file changed on disk",
        },
      },
    },
  },
}
