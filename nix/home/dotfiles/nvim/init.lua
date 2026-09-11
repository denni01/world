-- Order matters: leader before lazy, colorschemes on the rtp before theme.
require("config.options")
require("config.lazy")
require("config.theme").setup()
require("config.keymaps")
require("config.autocmds")
