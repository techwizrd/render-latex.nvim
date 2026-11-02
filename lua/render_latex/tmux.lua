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

function M.option(name)
  local result = run_tmux({ "show-options", "-qvg", name })
  return result.code == 0 and vim.trim(result.stdout or "") or nil
end

--- The attached client's terminal as it answered XTVERSION, such as "ghostty 1.2.0".
--- Empty when the terminal didn't answer, nil when tmux can't be asked.
---@return string?
function M.client_termtype()
  local result = run_tmux({ "display-message", "-p", "#{client_termtype}" })
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
