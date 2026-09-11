-- Leader must be set before lazy loads, or plugin `keys` bind the old one.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local o = vim.o

o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.cursorline = true
o.scrolloff = 8
o.wrap = false
o.splitright = true
o.splitbelow = true

-- Solid block in every mode.
o.guicursor = ""

-- Fallback only: .editorconfig wins, then guess-indent, then this.
-- `:verbose set shiftwidth?` says which won.
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.softtabstop = 2
o.smartindent = true

o.ignorecase = true
o.smartcase = true
o.hlsearch = false
o.incsearch = true

o.undofile = true
o.swapfile = false
o.backup = false

o.updatetime = 250
o.timeoutlen = 300
o.termguicolors = true
o.mouse = "a"
o.clipboard = "unnamedplus"
o.breakindent = true
o.confirm = true

vim.diagnostic.config({
  virtual_text = { prefix = "-" },
  severity_sort = true,
  float = { border = "single", source = true },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "E",
      [vim.diagnostic.severity.WARN] = "W",
      [vim.diagnostic.severity.INFO] = "I",
      [vim.diagnostic.severity.HINT] = "H",
    },
  },
})
