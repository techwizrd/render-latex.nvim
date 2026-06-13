local M = {}

local Config = require("render_latex.config")

function M.has_popup_or_floating_windows()
  if vim.fn.pumvisible() == 1 then
    return true
  end

  if not Config.render.hide_on_cmdline and vim.fn.getcmdtype() ~= "" then
    return false
  end

  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(winid)
    if cfg.relative ~= nil and cfg.relative ~= "" and cfg.focusable ~= false then
      return true
    end
  end
  return false
end

return M
