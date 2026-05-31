local bit = require("bit")

local M = {}

local state = {}
local next_counter = 30
local pid_bits = 10
local cached_pid = nil
local batch_depth = 0
local batch_queue = {}

local function current_pid_bits()
  if cached_pid ~= nil then
    return cached_pid
  end

  local pid = vim.fn.getpid()
  cached_pid = bit.band(bit.bxor(pid, bit.rshift(pid, 5), bit.rshift(pid, pid_bits)), 0x3FF)
  return cached_pid
end

local function generate_id()
  next_counter = next_counter + 1
  return bit.bor(bit.lshift(current_pid_bits(), 24 - pid_bits), next_counter)
end

local function seq(control, payload)
  local parts = { "\027_G" }
  local tmp = {}
  for key, value in pairs(control) do
    tmp[#tmp + 1] = key .. "=" .. value
  end
  if #tmp > 0 then
    parts[#parts + 1] = table.concat(tmp, ",")
  end
  if payload and payload ~= "" then
    parts[#parts + 1] = ";"
    parts[#parts + 1] = payload
  end
  parts[#parts + 1] = "\027\\"
  return table.concat(parts)
end

local function tmux_wrap(data)
  if vim.env.TMUX == nil or vim.env.TMUX == "" then
    return data
  end

  local rep = tonumber(vim.env.TMUX_NEST_COUNT) or 1
  local wrapped = data:gsub("\027", string.rep("\027", 2 ^ rep))
  local header, tail = "", ""
  for index = 1, rep do
    header = header .. string.rep("\027", 2 ^ (index - 1)) .. "Ptmux;"
    tail = tail .. string.rep("\027", 2 ^ (rep - index)) .. "\\"
  end
  return header .. wrapped .. tail
end

local function send(data)
  data = tmux_wrap(data)
  if type(vim.api.nvim_ui_send) == "function" then
    vim.api.nvim_ui_send(data)
    return
  end

  local stderr = tonumber(vim.v.stderr)
  if type(vim.api.nvim_chan_send) == "function" and stderr ~= nil and stderr > 0 then
    vim.api.nvim_chan_send(stderr, data)
    return
  end

  error("raw terminal output is unavailable for Kitty graphics")
end

local function send_batched(data)
  if batch_depth > 0 then
    batch_queue[#batch_queue + 1] = data
    return
  end
  send(data)
end

local function transmit(img_id, data)
  local chunk_size = 4096
  local base64_data = vim.base64.encode(data)
  local pos = 1
  while pos <= #base64_data do
    local end_pos = math.min(pos + chunk_size - 1, #base64_data)
    local chunk = base64_data:sub(pos, end_pos)
    local is_last = end_pos >= #base64_data
    local control = { m = is_last and "0" or "1" }
    if pos == 1 then
      control.f = "100"
      control.a = "t"
      control.t = "d"
      control.i = img_id
      control.q = "2"
    end
    send_batched(seq(control, chunk))
    pos = end_pos + 1
  end
end

local function place(img_id, placement_id, opts)
  local control = {
    a = "p",
    i = img_id,
    p = placement_id,
    C = "1",
    q = "2",
  }
  if opts.width then
    control.c = opts.width
  end
  if opts.height then
    control.r = opts.height
  end
  if opts.zindex then
    control.z = opts.zindex
  end

  local cursor = table.concat({
    "\0277",
    "\027[?25l",
    string.format("\027[%d;%dH", opts.row or 1, opts.col or 1),
    seq(control),
    "\0278",
    "\027[?25h",
  })
  send_batched(cursor)
end

function M.set(data_or_id, opts)
  opts = opts or {}
  if type(data_or_id) == "string" then
    local img_id = generate_id()
    local placement_id = generate_id()
    transmit(img_id, data_or_id)
    place(img_id, placement_id, opts)
    state[placement_id] = {
      img_id = img_id,
      opts = vim.deepcopy(opts),
    }
    return placement_id
  end

  local entry = state[data_or_id]
  assert(entry ~= nil, "invalid image id: " .. tostring(data_or_id))
  local merged = vim.tbl_extend("force", entry.opts, opts)
  place(entry.img_id, data_or_id, merged)
  entry.opts = merged
  return data_or_id
end

function M.get(id)
  local entry = state[id]
  return entry and vim.deepcopy(entry.opts) or nil
end

function M.del(id)
  if id == math.huge then
    local has_ids = next(state) ~= nil
    state = {}
    if has_ids then
      send_batched(seq({ a = "d", d = "A", q = "2" }))
    end
    return has_ids
  end

  local entry = state[id]
  if entry == nil then
    return false
  end

  send_batched(seq({ a = "d", d = "i", i = entry.img_id, q = "2" }))
  state[id] = nil
  return true
end

function M.begin_batch()
  batch_depth = batch_depth + 1
end

function M.flush_batch()
  if batch_depth == 0 then
    return
  end

  batch_depth = batch_depth - 1
  if batch_depth > 0 or #batch_queue == 0 then
    return
  end

  local payload = table.concat(batch_queue)
  batch_queue = {}
  send(payload)
end

function M.supported()
  return vim.fn.executable("tmux") == 1 or vim.env.TMUX == nil
end

return M
