local Config = require("render_latex.config")
local Install = require("render_latex.install")
local Util = require("render_latex.util")

local M = {}
local request_timeout_ms = 30000

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
  generation = 0,
}

local function stderr_tail()
  local stderr = vim.trim(table.concat(state.stderr_chunks))
  if stderr == "" then
    return nil
  end
  if #stderr > 1000 then
    stderr = stderr:sub(#stderr - 999)
  end
  return stderr
end

local function close_handle(handle)
  if handle ~= nil and not handle:is_closing() then
    handle:close()
  end
end

local function kill_handle(handle)
  if handle ~= nil and not handle:is_closing() then
    pcall(handle.kill, handle, "sigterm")
  end
end

local function close_handles(handle, stdin, stdout, stderr, kill)
  if kill then
    kill_handle(handle)
  end
  close_handle(handle)
  close_handle(stdin)
  close_handle(stdout)
  close_handle(stderr)
end

local function close_process_handles(kill)
  close_handles(state.handle, state.stdin, state.stdout, state.stderr, kill)
end

local function active_process(handle, generation)
  return state.handle == handle and state.generation == generation
end

local function reset_state(notify_pending, reason)
  local stderr = stderr_tail()
  local exit_err = reason or (stderr ~= nil and ("worker exited: " .. stderr) or "worker exited")
  for id, pending in pairs(state.pending) do
    if pending.timer ~= nil and not pending.timer:is_closing() then
      pending.timer:stop()
      pending.timer:close()
    end
    if notify_pending then
      pending.callback(nil, exit_err)
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

local function complete_pending(id, result, err)
  local pending = state.pending[id]
  if pending == nil then
    return
  end
  state.pending[id] = nil
  if pending.timer ~= nil and not pending.timer:is_closing() then
    pending.timer:stop()
    pending.timer:close()
  end
  pending.callback(result, err)
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
      if state.pending[message.id] ~= nil then
        if message.error ~= nil then
          complete_pending(message.id, nil, message.error.message)
        else
          complete_pending(message.id, message.result, nil)
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
    if Install.status().building then
      return false, "worker building"
    end
    Util.error(
      "render-latex worker not found. Run :RenderLatex install, :RenderLatex build, or configure worker.bin."
    )
    return false, "worker unavailable"
  end

  local stdin = vim.uv.new_pipe(false)
  local stdout = vim.uv.new_pipe(false)
  local stderr = vim.uv.new_pipe(false)
  state.generation = state.generation + 1
  local generation = state.generation

  local handle, pid_or_err = vim.uv.spawn(bin, {
    args = Config.worker.args,
    cwd = Util.root(),
    stdio = { stdin, stdout, stderr },
  }, function()
    vim.schedule(function()
      if not active_process(handle, generation) then
        close_handles(handle, stdin, stdout, stderr, false)
        return
      end
      close_process_handles(false)
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
  local timer = vim.uv.new_timer()
  state.pending[id] = { callback = callback, timer = timer }
  timer:start(request_timeout_ms, 0, function()
    vim.schedule(function()
      if state.pending[id] == nil then
        return
      end
      close_process_handles(true)
      reset_state(true, "worker request timed out")
    end)
  end)

  local message = vim.json.encode({
    id = id,
    method = method,
    params = params,
  })
  local frame = ("Content-Length: %d\r\n\r\n%s"):format(#message, message)

  state.stdin:write(frame, function(err)
    if err == nil then
      return
    end
    vim.schedule(function()
      if state.pending[id] ~= nil then
        complete_pending(id, nil, "worker write failed: " .. tostring(err))
      end
    end)
  end)
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
  close_process_handles(false)
  reset_state(false)
end

function M.status()
  return {
    running = state.handle ~= nil,
    pending = vim.tbl_count(state.pending),
  }
end

function M.set_request_timeout_for_tests(timeout_ms)
  request_timeout_ms = timeout_ms
end

return M
