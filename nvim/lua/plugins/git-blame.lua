-- Git blame line integration
return {
  "f-person/git-blame.nvim",
  cmd = { "GitBlameToggle", "GitBlameEnable", "GitBlameDisable" },
  opts = {
    enabled = false, -- Start disabled, can be toggled
    message_template = " <summary> • <date> • <author>",
    date_format = "%m-%d-%Y %H:%M:%S",
    virtual_text_column = 1,
  },
}
