-- Yazi init.lua

-- Git plugin setup - shows git status as linemode in file list
-- Signs: M=modified, A=added, ?=untracked, !=ignored, D=deleted
require("git"):setup {
  order = 1500,
}
