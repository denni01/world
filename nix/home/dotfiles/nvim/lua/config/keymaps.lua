-- Plugin keymaps live in their own spec under `keys`, as load triggers.
-- 0.11 made K/grn/gra/grr/gri/gO defaults, so they are not restated here.
local map = vim.keymap.set

map({ "n", "v" }, "<Space>", "<Nop>", { silent = true })

-- Screen lines when wrapped, unless a count was given.
map("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
map("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })

-- Half-page scroll, recentred.
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- Keep the unnamed register when pasting over a selection.
map("x", "<leader>p", [["_dP]], { desc = "Paste without yanking" })

-- Tabs.
map("n", "]b", "<cmd>tabnext<cr>", { desc = "Next tab" })
map("n", "[b", "<cmd>tabprevious<cr>", { desc = "Previous tab" })
map("n", "<C-n>", "<cmd>tabnew<cr>", { desc = "New tab" })

-- Matches the Hyprland bindings.
map("n", "<C-h>", "<C-w>h", { desc = "Focus window left" })
map("n", "<C-j>", "<C-w>j", { desc = "Focus window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Focus window up" })
map("n", "<C-l>", "<C-w>l", { desc = "Focus window right" })

map("n", "[d", function()
  vim.diagnostic.jump({ count = -1, float = true })
end, { desc = "Previous diagnostic" })
map("n", "]d", function()
  vim.diagnostic.jump({ count = 1, float = true })
end, { desc = "Next diagnostic" })
map("n", "<leader>e", vim.diagnostic.open_float, { desc = "Show diagnostic" })
map("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Diagnostics to loclist" })

map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })

map("n", "<leader>2", function()
  vim.wo.signcolumn = vim.wo.signcolumn == "no" and "yes" or "no"
end, { desc = "Toggle sign column" })
