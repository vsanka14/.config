return {
  "sphamba/smear-cursor.nvim",
  lazy = true,
  event = "VeryLazy", -- Load after startup is complete
  -- Smooth cursor - optimized for speed
  opts = {
    stiffness = 0.5,
    trailing_stiffness = 0.5,
    matrix_pixel_threshold = 0.5,
  },
}
