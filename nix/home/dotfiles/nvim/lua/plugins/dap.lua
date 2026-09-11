-- Node/TS, Go, Rust, Swift. Adapters come from Nix and are found on $PATH — a
-- store path written here would go stale. If <F5> does nothing, check:
--   :lua =vim.fn.exepath("js-debug")
return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      -- nvim-dap-ui needs this.
      { "nvim-neotest/nvim-nio" },
      {
        "rcarriga/nvim-dap-ui",
        opts = {
          icons = { expanded = "v", collapsed = ">", current_frame = "*" },
          controls = { enabled = false },
        },
      },
      {
        "theHamsta/nvim-dap-virtual-text",
        opts = {
          virt_text_pos = "eol",
          display_callback = function(variable)
            return " = " .. variable.value:gsub("%s+", " ")
          end,
        },
      },
      { "leoluz/nvim-dap-go", opts = {} },
    },

    keys = {
      { "<F5>", function() require("dap").continue() end, desc = "Debug: start/continue" },
      { "<F1>", function() require("dap").step_into() end, desc = "Debug: step into" },
      { "<F2>", function() require("dap").step_over() end, desc = "Debug: step over" },
      { "<F3>", function() require("dap").step_out() end, desc = "Debug: step out" },
      { "<leader>b", function() require("dap").toggle_breakpoint() end, desc = "Debug: toggle breakpoint" },
      {
        "<leader>B",
        function()
          require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
        end,
        desc = "Debug: conditional breakpoint",
      },
      { "<leader>dt", function() require("dapui").toggle() end, desc = "Debug: toggle UI" },
      { "<leader>dr", function() require("dap").repl.toggle() end, desc = "Debug: REPL" },
      { "<leader>dx", function() require("dap").terminate() end, desc = "Debug: terminate" },
    },

    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      vim.fn.sign_define("DapBreakpoint", { text = "B", texthl = "DiagnosticError" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "C", texthl = "DiagnosticError" })
      vim.fn.sign_define("DapStopped", { text = ">", texthl = "DiagnosticWarn" })

      dap.listeners.after.event_initialized["dapui_config"] = dapui.open
      dap.listeners.before.event_terminated["dapui_config"] = dapui.close
      dap.listeners.before.event_exited["dapui_config"] = dapui.close

      -- js-debug as a DAP server; nvim-dap substitutes ${port}. Configured
      -- directly — nvim-dap-vscode-js is unmaintained and did only this.
      local js_debug = vim.fn.exepath("js-debug")
      if js_debug ~= "" then
        for _, adapter in ipairs({ "pwa-node", "pwa-chrome" }) do
          dap.adapters[adapter] = {
            type = "server",
            host = "127.0.0.1",
            port = "${port}",
            executable = { command = js_debug, args = { "${port}", "127.0.0.1" } },
          }
        end
      end

      -- sourceMaps so breakpoints land in .ts, not the emitted .js.
      local js_configs = {
        {
          type = "pwa-node",
          request = "launch",
          name = "Launch file (tsx)",
          runtimeExecutable = "tsx",
          program = "${file}",
          cwd = "${workspaceFolder}",
          sourceMaps = true,
          skipFiles = { "<node_internals>/**", "**/node_modules/**" },
        },
        {
          type = "pwa-node",
          request = "launch",
          name = "Launch file (node)",
          program = "${file}",
          cwd = "${workspaceFolder}",
          sourceMaps = true,
          skipFiles = { "<node_internals>/**", "**/node_modules/**" },
        },
        {
          -- For Express: run `node --inspect ./dist/server.js`, attach, hit a
          -- route.
          type = "pwa-node",
          request = "attach",
          name = "Attach to process (--inspect)",
          processId = require("dap.utils").pick_process,
          cwd = "${workspaceFolder}",
          sourceMaps = true,
          skipFiles = { "<node_internals>/**", "**/node_modules/**" },
        },
      }

      for _, ft in ipairs({ "javascript", "typescript", "javascriptreact", "typescriptreact" }) do
        dap.configurations[ft] = js_configs
      end

      -- Swift. Rust uses codelldb via rustaceanvim instead.
      local lldb_dap = vim.fn.exepath("lldb-dap")
      if lldb_dap ~= "" then
        dap.adapters.lldb = { type = "executable", command = lldb_dap, name = "lldb" }
        dap.configurations.swift = {
          {
            name = "Launch",
            type = "lldb",
            request = "launch",
            program = function()
              local guess = vim.fn.getcwd() .. "/.build/debug/" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
              return vim.fn.input("Path to executable: ", guess, "file")
            end,
            cwd = "${workspaceFolder}",
            stopOnEntry = false,
          },
        }
      end
    end,
  },
}
