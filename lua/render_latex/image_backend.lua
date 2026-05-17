local Config = require("render_latex.config")

local M = {}
local listeners = {}
local probe = {
  status = "unknown",
  pending = false,
  request_id = 30,
  autocmd = nil,
}

local function is_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

local function use_builtin()
  return vim.ui.img ~= nil and type(vim.ui.img.set) == "function"
end

local function notify_listeners(status)
  for _, listener in ipairs(listeners) do
    pcall(listener, status)
  end
end

local function cleanup_probe()
  if probe.autocmd ~= nil then
    pcall(vim.api.nvim_del_autocmd, probe.autocmd)
    probe.autocmd = nil
  end
end

local function finish_probe(status)
  local changed = probe.status ~= status
  probe.status = status
  probe.pending = false
  cleanup_probe()
  if changed then
    notify_listeners(status)
  end
end

local function start_probe()
  if is_tmux() or probe.pending or probe.status ~= "unknown" then
    return
  end

  probe.pending = true
  probe.request_id = probe.request_id + 1
  local request_id = probe.request_id
  probe.autocmd = vim.api.nvim_create_autocmd("TermResponse", {
    callback = function(ev)
      local sequence = ev.data.sequence
      local response_id = tonumber(sequence:match("\027_Gi=(%d+);"))
      if response_id == request_id then
        finish_probe("supported")
        return
      end

      if sequence:match("^\027%[[%?%d;>]*c") then
        finish_probe("unsupported")
      end
    end,
  })

  vim.api.nvim_ui_send(("\027_Gi=%d,s=1,v=1,a=q,t=d,f=24;AAAA\027\\\027[c"):format(request_id))
  vim.defer_fn(function()
    if probe.pending and probe.request_id == request_id then
      finish_probe("unsupported")
    end
  end, 200)
end

local function kitty_supported()
  if is_tmux() then
    return vim.fn.executable("tmux") == 1
  end
  if
    vim.env.KITTY_WINDOW_ID ~= nil
    or vim.env.WEZTERM_EXECUTABLE ~= nil
    or (vim.env.TERM or ""):lower():find("kitty", 1, true) ~= nil
  then
    return true
  end
  if probe.status == "unknown" then
    start_probe()
  end
  return probe.status == "supported"
end

function M.detect_name()
  if Config.image.backend == "nvim" then
    return "nvim"
  end
  if Config.image.backend == "kitty" then
    return "kitty"
  end
  if is_tmux() then
    return "kitty"
  end
  if use_builtin() then
    return "nvim"
  end
  return "kitty"
end

function M.get()
  local name = M.detect_name()
  if name == "nvim" and use_builtin() then
    return require("render_latex.image_backends.nvim"), name
  end
  if name == "nvim" then
    return nil, name, "vim.ui.img is unavailable"
  end
  if kitty_supported() then
    return require("render_latex.image_backends.kitty"), "kitty"
  end
  return nil, name, "kitty image protocol is not available in this terminal"
end

function M.status()
  local backend, name, reason = M.get()
  return {
    name = name,
    available = backend ~= nil,
    reason = reason,
    tmux = is_tmux(),
    builtin_available = use_builtin(),
    kitty_available = kitty_supported(),
    kitty_probing = probe.pending,
  }
end

function M.on_change(listener)
  listeners[#listeners + 1] = listener
end

function M.reset_for_tests()
  cleanup_probe()
  probe.status = "unknown"
  probe.pending = false
  probe.request_id = 30
end

return M
