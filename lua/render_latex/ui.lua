local M = {}

local Config = require("render_latex.config")

function M.floating_windows()
  local floats = {}
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(winid)
    if cfg.relative ~= nil and cfg.relative ~= "" then
      floats[#floats + 1] = {
        winid = winid,
        relative = cfg.relative,
        focusable = cfg.focusable,
        zindex = cfg.zindex,
        row = cfg.row,
        col = cfg.col,
        width = cfg.width,
        height = cfg.height,
      }
    end
  end
  return floats
end

function M.has_popup_or_floating_windows()
  if vim.fn.pumvisible() == 1 then
    return true
  end

  return Config.render.hide_on_cmdline and vim.fn.getcmdtype() ~= ""
end

return M
