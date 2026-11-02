local M = {}

local REQUIRED_HOOKS = {
  "session-window-changed",
  "client-session-changed",
  "window-pane-changed",
}

local DELETE_SEQ = "\\033_Ga=d,d=A\\033\\\\"
local DELETE_COMMAND = [[run-shell "printf '\033_Ga=d,d=A\033\\' > #{client_tty}"]]

local function run_tmux(args)
  if vim.fn.executable("tmux") ~= 1 then
    return { code = 127, stdout = "", stderr = "tmux not found" }
  end
  return vim.system(vim.list_extend({ "tmux" }, args), { text = true }):wait()
end

-- Pids of the clients last seen on this pane's session
local known_clients = nil

--- Whether a client attached to this pane's session since the previous call. The first
--- call only records the clients. Kitty images live in each terminal, so a terminal that
--- attaches later has none of the images sent before it.
---@return boolean
function M.client_attached()
  if vim.env.TMUX == nil or vim.env.TMUX == "" then
    return false
  end

  local args = { "list-clients", "-F", "#{client_pid}" }
  local pane = vim.env.TMUX_PANE
  if pane ~= nil and pane ~= "" then
    vim.list_extend(args, { "-t", pane })
  end
  local result = run_tmux(args)
  if result.code ~= 0 then
    return false
  end

  local clients = {}
  for pid in (result.stdout or ""):gmatch("%d+") do
    clients[pid] = true
  end
  local previous = known_clients
  known_clients = clients
  if previous == nil then
    return false
  end
  for pid in pairs(clients) do
    if not previous[pid] then
      return true
    end
  end
  return false
end

function M.option(name)
  local result = run_tmux({ "show-options", "-qvg", name })
  return result.code == 0 and vim.trim(result.stdout or "") or nil
end

---@param global boolean
function M.hooks(global)
  local args = { "show-hooks" }
  if global then
    args[#args + 1] = "-g"
  end

  local result = run_tmux(args)
  if result.code ~= 0 then
    return {}
  end

  local hooks = {}
  for line in vim.gsplit(result.stdout or "", "\n", { plain = true }) do
    local name = line:match("^([%w%-]+)%[%d+%]%s") or line:match("^([%w%-]+)%s")
    if name ~= nil then
      hooks[name] = hooks[name] ~= nil and (hooks[name] .. "\n" .. line) or line
    end
  end
  return hooks
end

---@param global? boolean
function M.hook_status(global)
  local hooks = M.hooks(global == true)
  local status = {}
  for _, name in ipairs(REQUIRED_HOOKS) do
    local line = hooks[name]
    status[#status + 1] = {
      name = name,
      present = line ~= nil,
      valid = line ~= nil and line:find(DELETE_SEQ, 1, false) ~= nil,
      line = line,
    }
  end
  return status
end

function M.install_cleanup_hooks()
  if vim.env.TMUX == nil or vim.env.TMUX == "" then
    return true
  end

  local ok = true
  for _, hook in ipairs(M.hook_status(false)) do
    if not hook.valid then
      local result = run_tmux({ "set-hook", "-a", hook.name, DELETE_COMMAND })
      ok = ok and result.code == 0
    end
  end
  return ok
end

return M
