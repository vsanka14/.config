-- vim-matchup - Enhanced bracket/keyword matching with visual highlighting
return {
  "andymass/vim-matchup",
  event = "BufReadPost",
  init = function()
    -- Disable the built-in matchparen (vim-matchup replaces it)
    vim.g.loaded_matchparen = 1
  end,
  config = function()
    vim.g.matchup_matchparen_offscreen = { method = "popup" } -- Show matching bracket in popup when off-screen
    vim.g.matchup_matchparen_deferred = 1 -- Improve performance with deferred highlighting
    vim.g.matchup_matchparen_hi_surround_always = 1 -- Always highlight surrounding brackets
  end,
}
