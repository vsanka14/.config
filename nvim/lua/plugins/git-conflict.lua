-- Better merge conflict highlighting and resolution
return {
  "akinsho/git-conflict.nvim",
  version = "*",
  event = "BufReadPre",
  opts = {
    default_mappings = true, -- disable if you want custom mappings
    default_commands = true,
    disable_diagnostics = false,
    list_opener = "copen",
    highlights = {
      incoming = "DiffAdd",
      current = "DiffText",
    },
  },
  -- Default keymaps:
  -- co — choose ours (current/HEAD)
  -- ct — choose theirs (incoming)
  -- cb — choose both
  -- c0 — choose none
  -- ]x — move to next conflict
  -- [x — move to previous conflict
}
