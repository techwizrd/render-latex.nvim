local M = {}

local root

function M.root()
  if root ~= nil then
    return root
  end

  local source = debug.getinfo(1, "S").source:sub(2)
  root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
  return root
end

---@param msg string
---@param level integer
function M.notify(msg, level)
  vim.notify(msg, level, { title = "render-latex.nvim" })
end

---@param msg string
function M.info(msg)
  M.notify(msg, vim.log.levels.INFO)
end

---@param msg string
function M.warn(msg)
  M.notify(msg, vim.log.levels.WARN)
end

---@param msg string
function M.error(msg)
  M.notify(msg, vim.log.levels.ERROR)
end

---@param bufnr integer
function M.buf_is_valid(bufnr)
  return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted
end

---@param winid integer
function M.win_is_valid(winid)
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

---@param winid integer
function M.win_is_normal(winid)
  if not M.win_is_valid(winid) then
    return false
  end
  local cfg = vim.api.nvim_win_get_config(winid)
  return cfg.relative == nil or cfg.relative == ""
end

---@return integer[]
function M.current_tab_normal_wins()
  local wins = {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if M.win_is_normal(winid) then
      wins[#wins + 1] = winid
    end
  end
  return wins
end

---@param bufnr integer
---@return integer[]
function M.current_tab_wins_for_buf(bufnr)
  local wins = {}
  for _, winid in ipairs(M.current_tab_normal_wins()) do
    if vim.api.nvim_win_get_buf(winid) == bufnr then
      wins[#wins + 1] = winid
    end
  end
  return wins
end

---@param value string
---@return string
function M.escape_pattern(value)
  local escaped = value:gsub("([^%w])", "%%%1")
  return escaped
end

---@param input string
---@return string
function M.sha256(input)
  return vim.fn.sha256(input)
end

---@param name string
---@return string?
function M.get_hl_hex(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = true })
  if not ok or type(hl) ~= "table" then
    return nil
  end

  local fg = hl.fg
  if type(fg) ~= "number" then
    return nil
  end

  return ("#%06x"):format(fg)
end

---@param names string[]
---@return string?, string?
function M.get_first_hl_hex(names)
  for _, name in ipairs(names) do
    local hex = M.get_hl_hex(name)
    if hex ~= nil then
      return hex, name
    end
  end
  return nil, nil
end

---@param value number
---@return integer
function M.round_up(value)
  return math.max(1, math.ceil(value))
end

---@param lines string[]
---@param filetype? string
---@return integer
function M.open_scratch(lines, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  if filetype ~= nil then
    vim.bo[buf].filetype = filetype
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_set_current_buf(buf)
  return buf
end

return M
