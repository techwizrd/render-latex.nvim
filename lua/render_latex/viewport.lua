local Config = require("render_latex.config")

local M = {}

---@param equation table
---@return boolean
function M.fold_closed(equation)
  return vim.fn.foldclosed(equation.start_row + 1) ~= -1
end

---@param line_count integer
---@return { disabled: boolean, prefetch: integer }
function M.render_limits(line_count)
  if line_count > Config.max_file_lines then
    return { disabled = true, prefetch = 0 }
  end

  if line_count > math.floor(Config.max_file_lines * 0.75) then
    return { disabled = false, prefetch = 0 }
  end

  if line_count > math.floor(Config.max_file_lines * 0.5) then
    return { disabled = false, prefetch = math.floor(Config.prefetch_lines / 4) }
  end

  return { disabled = false, prefetch = Config.prefetch_lines }
end

---@param viewport_state table<integer, { top: integer, bottom: integer, direction: 'up'|'down'|'still' }>
---@param winid integer
---@param prefetch integer
---@return integer, integer
function M.viewport_range(viewport_state, winid, prefetch)
  local top = vim.fn.line("w0", winid) - 1
  local bottom = vim.fn.line("w$", winid) - 1
  local previous = viewport_state[winid]
  local direction = "still"
  if previous ~= nil then
    if top > previous.top then
      direction = "down"
    elseif top < previous.top then
      direction = "up"
    else
      direction = previous.direction
    end
  end
  viewport_state[winid] = { top = top, bottom = bottom, direction = direction }

  if direction == "down" then
    return top - math.floor(prefetch / 3), bottom + prefetch
  elseif direction == "up" then
    return top - prefetch, bottom + math.floor(prefetch / 3)
  end

  return top - prefetch, bottom + prefetch
end

---@param winid integer
---@return integer?, integer?
function M.visible_text_bounds(winid)
  local top_lnum = vim.api.nvim_win_call(winid, function()
    return vim.fn.line("w0")
  end)
  local top = vim.fn.screenpos(winid, top_lnum, 1)
  if type(top) ~= "table" or top.row == 0 then
    return nil, nil
  end

  local text_top = top.row
  local text_bottom = text_top + vim.api.nvim_win_get_height(winid) - 1
  return text_top, text_bottom
end

---@param bufnr integer
---@param viewport_state table<integer, { top: integer, bottom: integer, direction: 'up'|'down'|'still' }>
---@param prefetch integer
---@return { top: integer, bottom: integer }[]
function M.viewport_ranges(bufnr, viewport_state, prefetch)
  local ranges = {}
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(winid) then
      local top, bottom = M.viewport_range(viewport_state, winid, prefetch)
      ranges[#ranges + 1] = { top = top, bottom = bottom }
    end
  end
  return ranges
end

---@param bufnr integer
---@param indexed_equations table[]
---@param viewport_state table<integer, { top: integer, bottom: integer, direction: 'up'|'down'|'still' }>
---@param prefetch integer
---@return table[]
function M.visible_equations(bufnr, indexed_equations, viewport_state, prefetch)
  local ranges = M.viewport_ranges(bufnr, viewport_state, prefetch)
  local visible = {}
  for _, equation in ipairs(indexed_equations) do
    if not M.fold_closed(equation) then
      for _, range in ipairs(ranges) do
        if equation.end_row >= range.top and equation.start_row <= range.bottom then
          visible[#visible + 1] = equation
          break
        end
      end
    end
  end
  return visible
end

return M
