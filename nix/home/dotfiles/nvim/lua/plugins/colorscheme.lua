-- Eager so :Theme can switch at runtime; a lazy scheme cannot be applied.
-- Italics are off in every scheme; each one spells it differently.
return {
  {
    "savq/melange-nvim",
    lazy = false,
    priority = 1000,
    -- Read when the scheme loads, so it has to be set before that.
    init = function()
      vim.g.melange_enable_font_variants = {
        bold = true,
        italic = false,
        underline = true,
        undercurl = true,
        strikethrough = true,
      }
    end,
  },

  {
    "rebelot/kanagawa.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      -- If you build your own, `overrides` here beats starting from scratch.
      dimInactive = false,
      terminalColors = true,
      commentStyle = { italic = false },
      keywordStyle = { italic = false },
    },
  },

  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",
      styles = {
        comments = { italic = false },
        keywords = { italic = false },
      },
    },
  },

  {
    "ellisonleao/gruvbox.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      contrast = "hard",
      transparent_mode = false,
      italic = {
        strings = false,
        emphasis = false,
        comments = false,
        operators = false,
        folds = false,
      },
    },
  },
}
