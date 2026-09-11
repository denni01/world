-- :Theme picks a colorscheme and persists it to stdpath("state"), so trying
-- one is not a config edit. Loaded after config.lazy so the schemes exist.
local M = {}

local state_file = vim.fn.stdpath("state") .. "/theme.txt"

M.themes = {
  { label = "melange (dark)", scheme = "melange", background = "dark" },
  { label = "melange (light)", scheme = "melange", background = "light" },
  { label = "kanagawa wave", scheme = "kanagawa-wave", background = "dark" },
  { label = "kanagawa dragon", scheme = "kanagawa-dragon", background = "dark" },
  { label = "kanagawa lotus", scheme = "kanagawa-lotus", background = "light" },
  { label = "tokyonight night", scheme = "tokyonight-night", background = "dark" },
  { label = "tokyonight storm", scheme = "tokyonight-storm", background = "dark" },
  { label = "tokyonight moon", scheme = "tokyonight-moon", background = "dark" },
  { label = "tokyonight day", scheme = "tokyonight-day", background = "light" },
  { label = "gruvbox (dark)", scheme = "gruvbox", background = "dark" },
  { label = "gruvbox (light)", scheme = "gruvbox", background = "light" },
}

local default = "melange (dark)"

local function find(label)
  for _, t in ipairs(M.themes) do
    if t.label == label then
      return t
    end
  end
end

local function read()
  local f = io.open(state_file, "r")
  if not f then
    return default
  end
  local label = f:read("l")
  f:close()
  return (label and find(label)) and label or default
end

local function write(label)
  local f = io.open(state_file, "w")
  if f then
    f:write(label, "\n")
    f:close()
  end
end

-- Schemes disagree on where italics live and several hardcode them.
local function strip_italics()
  for name, def in pairs(vim.api.nvim_get_hl(0, {})) do
    if def.italic then
      def.italic = nil
      vim.api.nvim_set_hl(0, name, def)
    end
  end
end

-- Fall back rather than erroring out of startup.
function M.apply(label, persist)
  local theme = find(label) or find(default)
  vim.o.background = theme.background
  local ok, err = pcall(vim.cmd.colorscheme, theme.scheme)
  if not ok then
    vim.notify(("theme %q failed to load (%s), using habamax"):format(theme.scheme, err), vim.log.levels.WARN)
    vim.cmd.colorscheme("habamax")
    return
  end
  if persist then
    write(theme.label)
  end
end

function M.pick()
  vim.ui.select(M.themes, {
    prompt = "Colorscheme",
    format_item = function(t)
      return t.label
    end,
  }, function(choice)
    if choice then
      M.apply(choice.label, true)
    end
  end)
end

function M.setup()
  vim.api.nvim_create_autocmd("ColorScheme", { callback = strip_italics })
  M.apply(read(), false)
  vim.api.nvim_create_user_command("Theme", M.pick, { desc = "Pick and persist a colorscheme" })
end

return M
