-- OpenCode AI assistant integration
return {
  "NickvanDyke/opencode.nvim",
  -- Note: snacks.nvim is already configured by AstroNvim with input/picker/terminal enabled
  config = function()
    ---@type opencode.Opts
    vim.g.opencode_opts = {
      -- Contexts to inject into prompts (placeholders like @this, @buffer, etc.)
      contexts = {
        -- Default contexts are already provided, you can add custom ones:
        -- ["@custom"] = function(context) return "custom context" end,
      },
      -- Custom prompts you can quickly select
      prompts = {
        -- Built-in prompts: diagnostics, diff, document, explain, fix, implement, optimize, review, test
        -- Add your own:
        refactor = { prompt = "Refactor @this to be more readable and maintainable", submit = true },
        types = { prompt = "Add TypeScript types to @this", submit = true },
        comment = { prompt = "Add helpful comments to @this explaining the logic", submit = true },
      },
      -- Ask input options
      ask = {
        prompt = "Ask OpenCode: ",
      },
      -- Events configuration
      events = {
        enabled = true, -- Subscribe to SSE events from opencode
        reload = true, -- Auto-reload buffers when opencode edits them
        permissions = {
          enabled = true,
          idle_delay_ms = 1000,
        },
      },
      -- Provider configuration - use WezTerm since you have it
      provider = {
        cmd = "opencode",
        enabled = "wezterm",
        wezterm = {
          direction = "right", -- Open opencode pane to the right
          percent = 40, -- Take 40% of the screen
        },
      },
    }

    -- Required for auto-reload feature
    vim.o.autoread = true
  end,
}
