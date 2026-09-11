-- blink.cmp over nvim-cmp (maintenance mode): it absorbs cmp-nvim-lsp and
-- cmp_luasnip too.
return {
  {
    "saghen/blink.cmp",
    event = "InsertEnter",
    version = "^1",
    dependencies = {
      {
        "L3MON4D3/LuaSnip",
        version = "^2",
        dependencies = { "rafamadriz/friendly-snippets" },
        config = function()
          require("luasnip.loaders.from_vscode").lazy_load()
        end,
      },
    },
    opts = {
      snippets = { preset = "luasnip" },

      -- C-n/C-p cycle, C-y accept, C-e cancel. Tab stays out of it so it
      -- cannot fight snippet jumping or indentation.
      keymap = {
        preset = "default",
        ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
      },

      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
        menu = {
          draw = {
            columns = { { "label", "label_description", gap = 1 }, { "source_name" } },
          },
        },
      },

      signature = { enabled = true },

      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
        providers = {
          -- Neovim API completions via blink, not LuaLS — avoids duplicates.
          lazydev = { name = "LazyDev", module = "lazydev.integrations.blink", score_offset = 100 },
        },
      },

      fuzzy = { implementation = "prefer_rust_with_warning" },
    },
    opts_extend = { "sources.default" },
  },
}
