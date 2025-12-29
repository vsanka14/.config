-- You can also add or configure plugins by creating files in this `plugins/` folder
-- Here are some examples:

---@type LazySpec
return {

  -- == Examples of Adding Plugins ==

  {
    "ray-x/lsp_signature.nvim",
    event = "BufRead",
    config = function() require("lsp_signature").setup() end,
  },

  -- == Examples of Overriding Plugins ==

  -- customize dashboard options
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = {
          header = (function()
            local headers = {
              {
                "███████╗██╗██╗  ██╗    ██╗      █████╗ ████████╗███████╗██████╗ ",
                "██╔════╝██║╚██╗██╔╝    ██║     ██╔══██╗╚══██╔══╝██╔════╝██╔══██╗",
                "█████╗  ██║ ╚███╔╝     ██║     ███████║   ██║   █████╗  ██████╔╝",
                "██╔══╝  ██║ ██╔██╗     ██║     ██╔══██║   ██║   ██╔══╝  ██╔══██╗",
                "██║     ██║██╔╝ ██╗    ███████╗██║  ██║   ██║   ███████╗██║  ██║",
                "╚═╝     ╚═╝╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝",
              },
              {
                "██╗    ██╗██╗███╗   ██╗ ██████╗ ██╗███╗   ██╗ ██████╗     ██╗████████╗",
                "██║    ██║██║████╗  ██║██╔════╝ ██║████╗  ██║██╔════╝     ██║╚══██╔══╝",
                "██║ █╗ ██║██║██╔██╗ ██║██║  ███╗██║██╔██╗ ██║██║  ███╗    ██║   ██║   ",
                "██║███╗██║██║██║╚██╗██║██║   ██║██║██║╚██╗██║██║   ██║    ██║   ██║   ",
                "╚███╔███╔╝██║██║ ╚████║╚██████╔╝██║██║ ╚████║╚██████╔╝    ██║   ██║   ",
                " ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝     ╚═╝   ╚═╝   ",
              },
              {
                "██╗   ██╗███╗   ██╗██████╗ ██████╗  ██████╗ ███╗   ███╗███████╗",
                "╚██╗ ██╔╝████╗  ██║██╔══██╗██╔══██╗██╔═══██╗████╗ ████║██╔════╝",
                " ╚████╔╝ ██╔██╗ ██║██║  ██║██████╔╝██║   ██║██╔████╔██║█████╗  ",
                "  ╚██╔╝  ██║╚██╗██║██║  ██║██╔══██╗██║   ██║██║╚██╔╝██║██╔══╝  ",
                "   ██║   ██║ ╚████║██████╔╝██║  ██║╚██████╔╝██║ ╚═╝ ██║███████╗",
                "   ╚═╝   ╚═╝  ╚═══╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝",
              },
              {
                "███████╗████████╗ █████╗  ██████╗██╗  ██╗     ██████╗ ██╗   ██╗███████╗██████╗ ",
                "██╔════╝╚══██╔══╝██╔══██╗██╔════╝██║ ██╔╝    ██╔═══██╗██║   ██║██╔════╝██╔══██╗",
                "███████╗   ██║   ███████║██║     █████╔╝     ██║   ██║██║   ██║█████╗  ██████╔╝",
                "╚════██║   ██║   ██╔══██║██║     ██╔═██╗     ██║   ██║╚██╗ ██╔╝██╔══╝  ██╔══██╗",
                "███████║   ██║   ██║  ██║╚██████╗██║  ██╗    ╚██████╔╝ ╚████╔╝ ███████╗██║  ██║",
                "╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝     ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═╝",
              },
              {
                "██████╗  █████╗ ███╗   ██╗██╗ ██████╗     ██████╗ ██████╗ ██████╗ ███████╗",
                "██╔══██╗██╔══██╗████╗  ██║██║██╔════╝    ██╔════╝██╔═══██╗██╔══██╗██╔════╝",
                "██████╔╝███████║██╔██╗ ██║██║██║         ██║     ██║   ██║██║  ██║█████╗  ",
                "██╔═══╝ ██╔══██║██║╚██╗██║██║██║         ██║     ██║   ██║██║  ██║██╔══╝  ",
                "██║     ██║  ██║██║ ╚████║██║╚██████╗    ╚██████╗╚██████╔╝██████╔╝███████╗",
                "╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝ ╚═════╝     ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝",
              },
            }
            math.randomseed(os.time())
            return table.concat(headers[math.random(#headers)], "\n")
          end)(),
        },
        sections = {
          { section = "header" },
          { section = "keys", gap = 1, padding = 1 },
          { section = "startup" },
        },
      },
    },
  },

  -- You can disable default plugins as follows:
  { "max397574/better-escape.nvim", enabled = false },

  -- == GitLens-like functionality ==
  
  -- Enhanced git signs with blame and diff
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      signs = {
        add = { text = "+" },
        change = { text = "~" },
        delete = { text = "_" },
        topdelete = { text = "‾" },
        changedelete = { text = "~" },
        untracked = { text = "┆" },
      },
      current_line_blame = true,
      current_line_blame_opts = {
        virt_text = true,
        virt_text_pos = "eol",
        delay = 500,
        ignore_whitespace = false,
      },
      current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",
      preview_config = {
        border = "single",
        style = "minimal",
        relative = "cursor",
        row = 0,
        col = 1,
      },
    },
  },

  -- Advanced git diff viewer and history
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles", "DiffviewFileHistory" },
    opts = {
      diff_binaries = false,
      enhanced_diff_hl = true,
      git_cmd = { "git" },
      hg_cmd = { "hg" },
      use_icons = true,
      show_help_hints = true,
      watch_index = true,
      icons = {
        folder_closed = "",
        folder_open = "",
      },
      signs = {
        fold_closed = "",
        fold_open = "",
        done = "✓",
      },
    },
  },

  -- Comprehensive git interface similar to GitLens
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
      "nvim-telescope/telescope.nvim",
    },
    cmd = "Neogit",
    opts = {
      disable_signs = false,
      disable_hint = false,
      disable_context_highlighting = false,
      disable_commit_confirmation = false,
      auto_refresh = true,
      disable_builtin_notifications = false,
      use_magit_keybindings = false,
      commit_popup = {
        kind = "split",
      },
      popup = {
        kind = "split",
      },
      signs = {
        section = { ">", "v" },
        item = { ">", "v" },
        hunk = { "", "" },
      },
      integrations = {
        diffview = true,
      },
    },
  },

  -- Git blame line integration
  {
    "f-person/git-blame.nvim",
    cmd = { "GitBlameToggle", "GitBlameEnable", "GitBlameDisable" },
    opts = {
      enabled = false, -- Start disabled, can be toggled
      message_template = " <summary> • <date> • <author>",
      date_format = "%m-%d-%Y %H:%M:%S",
      virtual_text_column = 1,
    },
  },

  -- Add Astro icon support to mini.icons
  {
    "echasnovski/mini.icons",
    opts = {
      extension = {
        astro = { glyph = "󱓞", hl = "MiniIconsOrange" },
      },
    },
  },

  -- Markdown preview in terminal using glow
  {
    "ellisonleao/glow.nvim",
    cmd = "Glow",
    ft = { "markdown", "mdx" },
    opts = {
      border = "rounded",
      width_ratio = 0.8,
      height_ratio = 0.8,
      width = 120,
      height = 100,
    },
  },

  -- Browser-based markdown preview (live reload)
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown", "mdx" },
    build = "cd app && npm install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown", "mdx" }
      vim.g.mkdp_auto_close = 0 -- Don't auto-close when switching buffers
      vim.g.mkdp_theme = "dark"
    end,
  },

  -- Show hidden files by default in Neo-tree
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      filesystem = {
        filtered_items = {
          visible = true,
          hide_dotfiles = false,
          hide_gitignored = false,
        },
      },
    },
  },

  -- You can also easily customize additional setup of plugins that is outside of the plugin's setup call
  {
    "L3MON4D3/LuaSnip",
    config = function(plugin, opts)
      require "astronvim.plugins.configs.luasnip"(plugin, opts) -- include the default astronvim config that calls the setup call
      -- add more custom luasnip configuration such as filetype extend or custom snippets
      local luasnip = require "luasnip"
      luasnip.filetype_extend("javascript", { "javascriptreact" })
    end,
  },

  {
    "windwp/nvim-autopairs",
    config = function(plugin, opts)
      require "astronvim.plugins.configs.nvim-autopairs"(plugin, opts) -- include the default astronvim config that calls the setup call
      -- add more custom autopairs configuration such as custom rules
      local npairs = require "nvim-autopairs"
      local Rule = require "nvim-autopairs.rule"
      local cond = require "nvim-autopairs.conds"
      npairs.add_rules(
        {
          Rule("$", "$", { "tex", "latex" })
            -- don't add a pair if the next character is %
            :with_pair(cond.not_after_regex "%%")
            -- don't add a pair if  the previous character is xxx
            :with_pair(
              cond.not_before_regex("xxx", 3)
            )
            -- don't move right when repeat character
            :with_move(cond.none())
            -- don't delete if the next character is xx
            :with_del(cond.not_after_regex "xx")
            -- disable adding a newline when you press <cr>
            :with_cr(cond.none()),
        },
        -- disable for .vim files, but it work for another filetypes
        Rule("a", "a", "-vim")
      )
    end,
  },
}
