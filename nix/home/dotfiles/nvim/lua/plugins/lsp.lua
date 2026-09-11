-- No mason: servers come from Nix (home.packages) and are found on $PATH.
-- 0.11+ owns the framework, so nvim-lspconfig is only data — never required.
return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "saghen/blink.cmp" },
    config = function()
      -- Servers merge over this '*' entry, rustaceanvim included.
      vim.lsp.config("*", {
        capabilities = require("blink.cmp").get_lsp_capabilities(),
      })

      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            workspace = { checkThirdParty = false },
            telemetry = { enable = false },
            diagnostics = { globals = { "vim" } },
          },
        },
      })

      vim.lsp.config("gopls", {
        settings = {
          gopls = {
            analyses = { unusedparams = true, shadow = true },
            staticcheck = true,
            gofumpt = true,
          },
        },
      })

      vim.lsp.config("vtsls", {
        settings = {
          typescript = {
            updateImportsOnFileMove = { enabled = "always" },
            inlayHints = {
              parameterNames = { enabled = "literals" },
              variableTypes = { enabled = false },
            },
          },
        },
      })

      vim.lsp.config("pyright", {
        settings = {
          python = {
            analysis = {
              typeCheckingMode = "strict",
              autoImportCompletions = true,
              autoSearchPaths = true,
              useLibraryCodeForTypes = true,
              diagnosticMode = "openFilesOnly",
            },
          },
        },
      })

      -- No rust_analyzer: rustaceanvim owns it, and two clients would attach.
      vim.lsp.enable({
        "lua_ls",
        "gopls",
        "vtsls",
        "pyright",
        "sourcekit", -- Swift
        "nixd",
      })

      -- Only what 0.11 did not make a default.
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("dennis_lsp_attach", { clear = true }),
        callback = function(event)
          local map = function(keys, fn, desc)
            vim.keymap.set("n", keys, fn, { buffer = event.buf, desc = "LSP: " .. desc })
          end
          local fzf = require("fzf-lua")
          map("gd", fzf.lsp_definitions, "Definition")
          map("gD", vim.lsp.buf.declaration, "Declaration")
          map("gy", fzf.lsp_typedefs, "Type definition")
          map("<leader>ds", fzf.lsp_document_symbols, "Document symbols")
          map("<leader>ws", fzf.lsp_live_workspace_symbols, "Workspace symbols")

          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client:supports_method("textDocument/inlayHint") then
            map("<leader>th", function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }), { bufnr = event.buf })
            end, "Toggle inlay hints")
          end
        end,
      })
    end,
  },

  -- Replaces neodev.nvim, archived 2024.
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
      library = {
        { path = "${3rd}/luv/library", words = { "vim%.uv" } },
      },
    },
  },

  -- rust-analyzer and codelldb in one. codelldb over lldb-dap for Rust: it has
  -- the type formatters, so a Vec/String renders as itself.
  {
    "mrcjkb/rustaceanvim",
    version = "^7",
    lazy = false, -- the plugin sets itself up on the Rust filetype
    init = function()
      local codelldb = vim.fn.exepath("codelldb")
      if codelldb == "" then
        return
      end
      vim.g.rustaceanvim = {
        dap = {
          adapter = {
            type = "server",
            host = "127.0.0.1",
            port = "${port}",
            executable = { command = codelldb, args = { "--port", "${port}" } },
          },
        },
      }
    end,
  },
}
