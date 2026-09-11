-- Picker, file browsing, git signs, indent detection, statusline.
return {
  -- Replaces telescope (unmaintained since 2024); same <leader>s* keymaps.
  {
    "ibhagwan/fzf-lua",
    cmd = "FzfLua",
    keys = {
      { "<leader>sf", "<cmd>FzfLua files<cr>", desc = "Search files" },
      { "<leader>sg", "<cmd>FzfLua live_grep<cr>", desc = "Search by grep" },
      { "<leader>sw", "<cmd>FzfLua grep_cword<cr>", desc = "Search word under cursor" },
      { "<leader>sh", "<cmd>FzfLua helptags<cr>", desc = "Search help" },
      { "<leader>sd", "<cmd>FzfLua diagnostics_document<cr>", desc = "Search diagnostics" },
      { "<leader>sr", "<cmd>FzfLua resume<cr>", desc = "Resume last search" },
      { "<leader>sk", "<cmd>FzfLua keymaps<cr>", desc = "Search keymaps" },
      { "<leader>?", "<cmd>FzfLua oldfiles<cr>", desc = "Recent files" },
      { "<leader><space>", "<cmd>FzfLua buffers<cr>", desc = "Buffers" },
      { "<leader>gf", "<cmd>FzfLua git_files<cr>", desc = "Git files" },
      { "<leader>/", "<cmd>FzfLua blines<cr>", desc = "Search in current buffer" },
    },
    opts = {
      "default-title",
      winopts = { border = "single", preview = { border = "single" } },
      files = { git_icons = false, file_icons = false },
      buffers = { file_icons = false },
    },
  },

  -- Replaces neo-tree, which was used as a transient full-window picker —
  -- which is what oil is. <leader>pv kept.
  {
    "stevearc/oil.nvim",
    lazy = false,
    keys = {
      { "<leader>pv", "<cmd>Oil<cr>", desc = "Open parent directory" },
      { "-", "<cmd>Oil<cr>", desc = "Open parent directory" },
    },
    opts = {
      default_file_explorer = true,
      columns = {}, -- no icon column
      view_options = { show_hidden = true },
      keymaps = {
        ["q"] = "actions.close",
      },
    },
  },

  -- lazygit covers the porcelain side.
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "+" },
        change = { text = "~" },
        delete = { text = "_" },
        topdelete = { text = "^" },
        changedelete = { text = "%" },
        untracked = { text = "|" },
      },
      on_attach = function(bufnr)
        local gs = require("gitsigns")
        local map = function(keys, fn, desc)
          vim.keymap.set("n", keys, fn, { buffer = bufnr, desc = "Git: " .. desc })
        end
        map("]c", function()
          if vim.wo.diff then
            vim.cmd.normal({ "]c", bang = true })
          else
            gs.nav_hunk("next")
          end
        end, "Next hunk")
        map("[c", function()
          if vim.wo.diff then
            vim.cmd.normal({ "[c", bang = true })
          else
            gs.nav_hunk("prev")
          end
        end, "Previous hunk")
        map("<leader>hp", gs.preview_hunk, "Preview hunk")
        map("<leader>hr", gs.reset_hunk, "Reset hunk")
        map("<leader>hb", function()
          gs.blame_line({ full = true })
        end, "Blame line")
      end,
    },
  },

  -- Step 2 of the three in config/options.lua. Over vim-sleuth, which
  -- rescans on every buffer read.
  {
    "nmac427/guess-indent.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      override_editorconfig = false,
    },
  },

  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "helix",
      icons = { mappings = false, rules = {} },
      spec = {
        { "<leader>s", group = "search" },
        { "<leader>h", group = "git hunk" },
        { "<leader>d", group = "debug" },
        { "<leader>t", group = "toggle" },
      },
    },
  },

  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = {
      options = {
        icons_enabled = false,
        theme = "auto", -- follows :Theme
        component_separators = "|",
        section_separators = "",
      },
      sections = {
        lualine_c = { { "filename", path = 1 } },
      },
    },
  },
}
