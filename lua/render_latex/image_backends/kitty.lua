local bit = require("bit")

local M = {}

local state = {}
-- Images shown through Unicode placeholders, keyed by the caller's key. Windows that
-- show the same equation share one image; each M.set_virtual call gets its own handle.
local virtual_images = {}
local handles = {}
local next_handle = 0
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

-- Kitty Unicode placeholders: U+10EEEE cells whose combining marks give the image row
-- and column, and whose foreground color gives the image id. The terminal draws the
-- image over these cells, so it moves, scrolls and hides with the text like a glyph.
local PLACEHOLDER = vim.fn.nr2char(0x10EEEE)
-- From kitty's rowcolumn-diacritics.txt: the n-th mark encodes row or column n - 1.
-- stylua: ignore
local diacritic_codes = {
  0x0305, 0x030D, 0x030E, 0x0310, 0x0312, 0x033D, 0x033E, 0x033F, 0x0346, 0x034A, 0x034B,
  0x034C, 0x0350, 0x0351, 0x0352, 0x0357, 0x035B, 0x0363, 0x0364, 0x0365, 0x0366, 0x0367,
  0x0368, 0x0369, 0x036A, 0x036B, 0x036C, 0x036D, 0x036E, 0x036F, 0x0483, 0x0484, 0x0485,
  0x0486, 0x0487, 0x0592, 0x0593, 0x0594, 0x0595, 0x0597, 0x0598, 0x0599, 0x059C, 0x059D,
  0x059E, 0x059F, 0x05A0, 0x05A1, 0x05A8, 0x05A9, 0x05AB, 0x05AC, 0x05AF, 0x05C4, 0x0610,
  0x0611, 0x0612, 0x0613, 0x0614, 0x0615, 0x0616, 0x0617, 0x0657, 0x0658, 0x0659, 0x065A,
  0x065B, 0x065D, 0x065E, 0x06D6, 0x06D7, 0x06D8, 0x06D9, 0x06DA, 0x06DB, 0x06DC, 0x06DF,
  0x06E0, 0x06E1, 0x06E2, 0x06E4, 0x06E7, 0x06E8, 0x06EB, 0x06EC, 0x0730, 0x0732, 0x0733,
  0x0735, 0x0736, 0x073A, 0x073D, 0x073F, 0x0740, 0x0741, 0x0743, 0x0745, 0x0747, 0x0749,
  0x074A, 0x07EB, 0x07EC, 0x07ED, 0x07EE, 0x07EF, 0x07F0, 0x07F1, 0x07F3, 0x0816, 0x0817,
  0x0818, 0x0819, 0x081B, 0x081C, 0x081D, 0x081E, 0x081F, 0x0820, 0x0821, 0x0822, 0x0823,
  0x0825, 0x0826, 0x0827, 0x0829, 0x082A, 0x082B, 0x082C, 0x082D, 0x0951, 0x0953, 0x0954,
  0x0F82, 0x0F83, 0x0F86, 0x0F87, 0x135D, 0x135E, 0x135F, 0x17DD, 0x193A, 0x1A17, 0x1A75,
  0x1A76, 0x1A77, 0x1A78, 0x1A79, 0x1A7A, 0x1A7B, 0x1A7C, 0x1B6B, 0x1B6D, 0x1B6E, 0x1B6F,
  0x1B70, 0x1B71, 0x1B72, 0x1B73, 0x1CD0, 0x1CD1, 0x1CD2, 0x1CDA, 0x1CDB, 0x1CE0, 0x1DC0,
  0x1DC1, 0x1DC3, 0x1DC4, 0x1DC5, 0x1DC6, 0x1DC7, 0x1DC8, 0x1DC9, 0x1DCB, 0x1DCC, 0x1DD1,
  0x1DD2, 0x1DD3, 0x1DD4, 0x1DD5, 0x1DD6, 0x1DD7, 0x1DD8, 0x1DD9, 0x1DDA, 0x1DDB, 0x1DDC,
  0x1DDD, 0x1DDE, 0x1DDF, 0x1DE0, 0x1DE1, 0x1DE2, 0x1DE3, 0x1DE4, 0x1DE5, 0x1DE6, 0x1DFE,
  0x20D0, 0x20D1, 0x20D4, 0x20D5, 0x20D6, 0x20D7, 0x20DB, 0x20DC, 0x20E1, 0x20E7, 0x20E9,
  0x20F0, 0x2CEF, 0x2CF0, 0x2CF1, 0x2DE0, 0x2DE1, 0x2DE2, 0x2DE3, 0x2DE4, 0x2DE5, 0x2DE6,
  0x2DE7, 0x2DE8, 0x2DE9, 0x2DEA, 0x2DEB, 0x2DEC, 0x2DED, 0x2DEE, 0x2DEF, 0x2DF0, 0x2DF1,
  0x2DF2, 0x2DF3, 0x2DF4, 0x2DF5, 0x2DF6, 0x2DF7, 0x2DF8, 0x2DF9, 0x2DFA, 0x2DFB, 0x2DFC,
  0x2DFD, 0x2DFE, 0x2DFF, 0xA66F, 0xA67C, 0xA67D, 0xA6F0, 0xA6F1, 0xA8E0, 0xA8E1, 0xA8E2,
  0xA8E3, 0xA8E4, 0xA8E5, 0xA8E6, 0xA8E7, 0xA8E8, 0xA8E9, 0xA8EA, 0xA8EB, 0xA8EC, 0xA8ED,
  0xA8EE, 0xA8EF, 0xA8F0, 0xA8F1, 0xAAB0, 0xAAB2, 0xAAB3, 0xAAB7, 0xAAB8, 0xAABE, 0xAABF,
  0xAAC1, 0xFE20, 0xFE21, 0xFE22, 0xFE23, 0xFE24, 0xFE25, 0xFE26, 0x10A0F, 0x10A38, 0x1D185,
  0x1D186, 0x1D187, 0x1D188, 0x1D189, 0x1D1AA, 0x1D1AB, 0x1D1AC, 0x1D1AD, 0x1D242, 0x1D243,
  0x1D244,
}
local diacritics = {}
for index, code in ipairs(diacritic_codes) do
  diacritics[index] = vim.fn.nr2char(code)
end

--- Largest image, in cells per side, that placeholders can address.
M.max_placeholder_cells = #diacritics

--- Whether images are shown with Unicode placeholders rather than at screen positions.
---@return boolean
function M.placeholders()
  local Config = require("render_latex.config")
  local setting = Config.image.placeholders
  if setting == false or not vim.o.termguicolors then
    -- The image id travels as a 24-bit foreground color
    return false
  end
  if setting == true then
    return true
  end
  -- WezTerm speaks Kitty graphics but has no Unicode placeholders
  local term_program = (vim.env.TERM_PROGRAM or ""):lower()
  return term_program ~= "wezterm"
    and (vim.env.WEZTERM_EXECUTABLE == nil or vim.env.WEZTERM_EXECUTABLE == "")
end

--- Placeholder text for one row of an image, `width` cells wide.
---@param row integer 1-based image row
---@param width integer
---@return string
function M.placeholder_row(row, width)
  local cells = {}
  local row_mark = diacritics[math.min(row, #diacritics)]
  for col = 1, math.min(width, #diacritics) do
    cells[#cells + 1] = PLACEHOLDER .. row_mark .. diacritics[col]
  end
  return table.concat(cells)
end

local function send_virtual(image, data)
  transmit(image.img_id, data)
  send_batched(seq({
    a = "p",
    U = "1",
    i = image.img_id,
    c = math.min(image.width, #diacritics),
    r = math.min(image.height, #diacritics),
    q = "2",
  }))
end

--- Sends an image once per `opts.key` and returns a handle to it. The terminal draws it
--- wherever placeholder text colored with M.image_id(handle) appears.
---@param data string PNG bytes
---@param opts { key: string, width: integer, height: integer }
---@return integer handle
function M.set_virtual(data, opts)
  local entry = virtual_images[opts.key]
  if entry == nil then
    entry = { img_id = generate_id(), width = opts.width, height = opts.height, refs = 0 }
    send_virtual(entry, data)
    virtual_images[opts.key] = entry
  end
  entry.refs = entry.refs + 1
  -- Negative, so handles never collide with the placement ids M.set returns
  next_handle = next_handle - 1
  handles[next_handle] = { key = opts.key, img_id = entry.img_id, opts = vim.deepcopy(opts) }
  return next_handle
end

--- Sends the images M.set_virtual sent before again, under the same ids, for a terminal
--- that attached after they were first sent: placeholder text already on screen then
--- draws without changing. `blobs` maps M.set_virtual keys to PNG bytes; images missing
--- from it are left alone.
---@param blobs table<string, string>
---@return integer count images sent
function M.resend_virtual(blobs)
  local count = 0
  for key, image in pairs(virtual_images) do
    local data = blobs[key]
    if data ~= nil then
      send_virtual(image, data)
      count = count + 1
    end
  end
  return count
end

---@param handle integer
---@return integer?
function M.image_id(handle)
  local entry = handles[handle]
  return entry and entry.img_id or nil
end

local function release_virtual(handle)
  local entry = handles[handle]
  handles[handle] = nil
  local image = virtual_images[entry.key]
  if image == nil then
    return
  end
  image.refs = image.refs - 1
  if image.refs <= 0 then
    virtual_images[entry.key] = nil
    send_batched(seq({ a = "d", d = "I", i = image.img_id, q = "2" }))
  end
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
  local entry = state[id] or handles[id]
  return entry and vim.deepcopy(entry.opts) or nil
end

function M.del(id)
  if id == math.huge then
    local has_ids = next(state) ~= nil or next(handles) ~= nil
    if next(state) ~= nil then
      send_batched(seq({ a = "d", d = "A", q = "2" }))
    end
    -- d=A leaves virtual placements alone: free only this instance's images
    for _, image in pairs(virtual_images) do
      send_batched(seq({ a = "d", d = "I", i = image.img_id, q = "2" }))
    end
    state = {}
    virtual_images = {}
    handles = {}
    return has_ids
  end

  if handles[id] ~= nil then
    release_virtual(id)
    return true
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
