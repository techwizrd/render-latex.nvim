local Config = require("render_latex.config")

local M = {}
local listeners = {}
local probe = {
  status = "unknown",
  pending = false,
  request_id = 30,
  autocmd = nil,
  unsupported_at = nil,
}

local tmux_passthrough = {
  value = nil,
  checked_at = 0,
}

local PROBE_TIMEOUT_MS = 500
local PROBE_RETRY_MS = 2000
local TMUX_CACHE_MS = 2000

local function is_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

local function use_builtin()
  return vim.ui.img ~= nil and type(vim.ui.img.set) == "function"
end

local function kitty_stderr_channel()
  local channel = tonumber(vim.v.stderr)
  if type(vim.api.nvim_chan_send) == "function" and channel ~= nil and channel > 0 then
    return channel
  end
  return nil
end

local function can_send_kitty()
  return type(vim.api.nvim_ui_send) == "function" or kitty_stderr_channel() ~= nil
end

local function send_kitty(data)
  if type(vim.api.nvim_ui_send) == "function" then
    vim.api.nvim_ui_send(data)
    return true
  end
  local channel = kitty_stderr_channel()
  if channel ~= nil then
    vim.api.nvim_chan_send(channel, data)
    return true
  end
  return false
end

local function env_present(name)
  return vim.env[name] ~= nil and vim.env[name] ~= ""
end

local function known_kitty_terminal()
  local term = (vim.env.TERM or ""):lower()
  local term_program = (vim.env.TERM_PROGRAM or ""):lower()
  return env_present("KITTY_WINDOW_ID")
    or env_present("WEZTERM_EXECUTABLE")
    or env_present("GHOSTTY_RESOURCES_DIR")
    or term:find("kitty", 1, true) ~= nil
    or term:find("ghostty", 1, true) ~= nil
    or term_program == "kitty"
    or term_program == "ghostty"
    or term_program == "wezterm"
end

local function tmux_passthrough_enabled()
  if not is_tmux() or vim.fn.executable("tmux") ~= 1 then
    return false
  end

  local now = vim.uv.now()
  if tmux_passthrough.value ~= nil and now - tmux_passthrough.checked_at < TMUX_CACHE_MS then
    return tmux_passthrough.value
  end

  local value = require("render_latex.tmux").option("allow-passthrough")
  tmux_passthrough.value = value == "on" or value == "all"
  tmux_passthrough.checked_at = now
  return tmux_passthrough.value
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
  probe.unsupported_at = status == "unsupported" and vim.uv.now() or nil
  cleanup_probe()
  if changed then
    notify_listeners(status)
  end
end

local function start_probe()
  if is_tmux() or probe.pending or probe.status ~= "unknown" or not can_send_kitty() then
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

      -- The DA response can arrive before the graphics response in compatible terminals.
    end,
  })

  send_kitty(("\027_Gi=%d,s=1,v=1,a=q,t=d,f=24;AAAA\027\\\027[c"):format(request_id))
  vim.defer_fn(function()
    if probe.pending and probe.request_id == request_id then
      finish_probe("unsupported")
    end
  end, PROBE_TIMEOUT_MS)
end

local function kitty_supported()
  if not can_send_kitty() then
    return false
  end
  if is_tmux() then
    return tmux_passthrough_enabled()
      and (known_kitty_terminal() or Config.image.backend == "kitty")
  end
  if known_kitty_terminal() then
    return true
  end
  if
    probe.status == "unsupported"
    and probe.unsupported_at ~= nil
    and vim.uv.now() - probe.unsupported_at >= PROBE_RETRY_MS
  then
    probe.status = "unknown"
    probe.unsupported_at = nil
  end
  if probe.status == "unknown" then
    start_probe()
  end
  return probe.status == "supported"
end

local function kitty_unavailable_reason()
  if not can_send_kitty() then
    return "raw terminal output is unavailable for Kitty graphics"
  end
  if is_tmux() and not tmux_passthrough_enabled() then
    return "tmux allow-passthrough is not enabled"
  end
  if is_tmux() and not known_kitty_terminal() then
    return "tmux outer terminal is not known to support Kitty graphics; set image.backend = 'kitty' to force it"
  end
  return "kitty image protocol is not available in this terminal"
end

function M.detect_name()
  if Config.image.backend == "nvim" then
    return "nvim"
  end
  if Config.image.backend == "kitty" then
    return "kitty"
  end
  if is_tmux() and kitty_supported() then
    return "kitty"
  end
  if use_builtin() then
    return "nvim"
  end
  if is_tmux() then
    return "kitty"
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
  return nil, name, kitty_unavailable_reason()
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
    tmux_passthrough = tmux_passthrough_enabled(),
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
  probe.unsupported_at = nil
  tmux_passthrough.value = nil
  tmux_passthrough.checked_at = 0
end

return M
