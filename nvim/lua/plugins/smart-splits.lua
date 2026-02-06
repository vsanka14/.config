-- Disable smart-splits tmux integration so Ctrl+hjkl stays within Neovim
-- Use Alt+hjkl (bound in tmux.conf) for cross-boundary pane switching

---@type LazySpec
return {
  "mrjones2014/smart-splits.nvim",
  opts = {
    multiplexer_integration = false,
    at_edge = "stop",
  },
}
