local Config = require("render_latex.config")
local Install = require("render_latex.install")
local Util = require("render_latex.util")

local M = {}

local state = {
  handle = nil,
  stdin = nil,
  stdout = nil,
  stderr = nil,
  buffer = "",
  next_id = 1,
  pending = {},
  stderr_chunks = {},
  stopping = false,
}

local function json_nil_to_nil(value)
  if value == vim.NIL then
    return nil
  end

  if type(value) == "table" then
    for key, child in pairs(value) do
      value[key] = json_nil_to_nil(child)
    end
  end

  return value
end

local function reset_state(notify_pending)
  for id, callback in pairs(state.pending) do
    if notify_pending then
      callback(nil, "worker exited")
    end
    state.pending[id] = nil
  end
  state.handle = nil
  state.stdin = nil
  state.stdout = nil
  state.stderr = nil
  state.buffer = ""
  state.stderr_chunks = {}
  state.stopping = false
end

local function parse_messages(chunk)
  state.buffer = state.buffer .. chunk
  while true do
    local header_start, header_end, length = state.buffer:find("^Content%-Length: (%d+)\r\n\r\n")
    if header_start == nil then
      return
    end

    local body_start = header_end + 1
    local body_end = body_start + tonumber(length) - 1
    if #state.buffer < body_end then
      return
    end

    local payload = state.buffer:sub(body_start, body_end)
    state.buffer = state.buffer:sub(body_end + 1)

    local ok, message = pcall(vim.json.decode, payload)
    if not ok then
      Util.error("Failed to decode worker response")
    else
      message.error = json_nil_to_nil(message.error)
      message.result = json_nil_to_nil(message.result)
      local callback = state.pending[message.id]
      if callback ~= nil then
        state.pending[message.id] = nil
        if message.error ~= nil then
          callback(nil, message.error.message)
        else
          callback(message.result, nil)
        end
      end
    end
  end
end

local function start_worker()
  if state.handle ~= nil then
    return true, nil
  end

  local bin = Install.ensure_worker_path()
  if bin == nil then
    if Install.status().installing then
      return false, "worker installing"
    end
    Util.error(
      "render-latex worker not found. Run :RenderLatex install, :RenderLatex build, or configure worker.bin."
    )
    return false, "worker unavailable"
  end

  local stdin = vim.uv.new_pipe(false)
  local stdout = vim.uv.new_pipe(false)
  local stderr = vim.uv.new_pipe(false)

  local handle, pid_or_err = vim.uv.spawn(bin, {
    args = Config.worker.args,
    cwd = Util.root(),
    stdio = { stdin, stdout, stderr },
  }, function()
    vim.schedule(function()
      reset_state(not state.stopping)
    end)
  end)

  if handle == nil then
    stdin:close()
    stdout:close()
    stderr:close()
    Util.error("Failed to start render-latex worker: " .. tostring(pid_or_err))
    return false, "worker unavailable"
  end

  state.handle = handle
  state.stdin = stdin
  state.stdout = stdout
  state.stderr = stderr

  stdout:read_start(function(err, chunk)
    if err ~= nil then
      vim.schedule(function()
        Util.error("render-latex worker stdout error: " .. err)
      end)
      return
    end
    if chunk == nil then
      return
    end
    vim.schedule(function()
      parse_messages(chunk)
    end)
  end)

  stderr:read_start(function(err, chunk)
    if err ~= nil or chunk == nil then
      return
    end
    table.insert(state.stderr_chunks, chunk)
  end)

  return true, nil
end

---@param method string
---@param params table
---@param callback fun(result: any, err: string?)
function M.request(method, params, callback)
  local ok, err = start_worker()
  if not ok then
    callback(nil, err or "worker unavailable")
    return
  end

  local id = state.next_id
  state.next_id = state.next_id + 1
  state.pending[id] = callback

  local message = vim.json.encode({
    id = id,
    method = method,
    params = params,
  })
  local frame = ("Content-Length: %d\r\n\r\n%s"):format(#message, message)

  state.stdin:write(frame)
end

---@param items table[]
---@param callback fun(result: any, err: string?)
function M.request_batch(items, callback)
  M.request("render_batch", { items = items }, callback)
end

function M.stop()
  if state.handle == nil then
    return
  end

  state.stopping = true
  M.request("shutdown", {}, function() end)
  if not state.handle:is_closing() then
    state.handle:close()
  end
  if state.stdin ~= nil and not state.stdin:is_closing() then
    state.stdin:close()
  end
  if state.stdout ~= nil and not state.stdout:is_closing() then
    state.stdout:close()
  end
  if state.stderr ~= nil and not state.stderr:is_closing() then
    state.stderr:close()
  end
  reset_state(false)
end

function M.status()
  return {
    running = state.handle ~= nil,
    pending = vim.tbl_count(state.pending),
  }
end

return M
