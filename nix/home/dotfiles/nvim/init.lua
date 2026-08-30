-- Placeholder. Your existing config gets ported here — see the Phase 6 notes.
--
-- Expect some staleness when you bring it over: this is nvim 0.12, where
-- vim.lsp.config/vim.lsp.enable have largely replaced nvim-lspconfig
-- boilerplate, and plugin-manager conventions have moved too. Worth deciding
-- then whether LSP servers and formatters come from Nix (reproducible, no
-- :Mason) or stay managed inside nvim.

vim.g.mapleader = " "

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.undofile = true
vim.opt.signcolumn = "yes"
vim.opt.termguicolors = true
vim.opt.clipboard = "unnamedplus"
