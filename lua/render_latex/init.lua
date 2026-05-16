---@class render_latex.Plugin
local M = {}

M.did_setup = false

local function should_attach(bufnr)
  local Config = require("render_latex.config")
  return Config.enabled and Config.is_filetype_supported(vim.bo[bufnr].filetype)
end

local function register_autocmds()
  local Config = require("render_latex.config")
  local Renderer = require("render_latex.renderer")
  local Ui = require("render_latex.ui")
  local Worker = require("render_latex.worker")

  vim.api.nvim_clear_autocmds({ group = Config.augroup })

  local function queue_visible_buffers()
    local seen = {}
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(winid)
      if cfg.relative == nil or cfg.relative == "" then
        local bufnr = vim.api.nvim_win_get_buf(winid)
        if not seen[bufnr] and should_attach(bufnr) then
          seen[bufnr] = true
          Renderer.attach(bufnr)
          Renderer.queue(bufnr)
        end
      end
    end
  end

  local function update_transient_ui_suppression(queue_after)
    local in_cmdline = vim.fn.getcmdtype() ~= ""
    Renderer.set_suppressed("cmdline", Config.render.hide_on_cmdline and in_cmdline)
    Renderer.set_suppressed("floating", Ui.has_popup_or_floating_windows())
    local status = Renderer.suppression_status()
    local allowed = not in_cmdline and not status.cmdline and not status.floating
    if queue_after and allowed then
      queue_visible_buffers()
    end
    return allowed
  end

  vim.api.nvim_create_autocmd({
    "BufEnter",
    "BufWinEnter",
    "InsertEnter",
    "InsertLeave",
    "CursorMoved",
    "CursorMovedI",
    "CompleteChanged",
    "CompleteDone",
    "WinScrolled",
    "WinResized",
    "ColorScheme",
  }, {
    group = Config.augroup,
    callback = function(args)
      local bufnr = args.buf or vim.api.nvim_get_current_buf()
      local allowed = update_transient_ui_suppression(false)
      if should_attach(bufnr) then
        Renderer.attach(bufnr)
        if allowed then
          Renderer.queue(bufnr)
        end
      else
        Renderer.detach(bufnr)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = Config.augroup,
    callback = function(args)
      local bufnr = args.buf or vim.api.nvim_get_current_buf()
      local allowed = update_transient_ui_suppression(false)
      if should_attach(bufnr) then
        Renderer.attach(bufnr)
        Renderer.on_text_changed(bufnr, allowed)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = Config.augroup,
    callback = function(args)
      Renderer.detach(args.buf)
      update_transient_ui_suppression(false)
    end,
  })

  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = Config.augroup,
    callback = function(args)
      Renderer.detach_window(args.buf, vim.api.nvim_get_current_win())
      update_transient_ui_suppression(false)
    end,
  })

  vim.api.nvim_create_autocmd({ "CmdlineEnter", "CmdlineChanged", "CmdlineLeave", "WinEnter" }, {
    group = Config.augroup,
    callback = function()
      update_transient_ui_suppression(true)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = Config.augroup,
    callback = function(args)
      local winid = tonumber(args.match)
      if winid ~= nil then
        Renderer.detach_winid(winid)
      end
      update_transient_ui_suppression(false)
    end,
  })

  vim.api.nvim_create_autocmd({ "FocusLost", "VimSuspend" }, {
    group = Config.augroup,
    callback = function()
      Renderer.clear_all()
    end,
  })

  vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, {
    group = Config.augroup,
    callback = function()
      update_transient_ui_suppression(true)
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = Config.augroup,
    callback = function()
      Renderer.clear_all()
      Worker.stop()
    end,
  })

  update_transient_ui_suppression(true)
  return queue_visible_buffers
end

---@param opts? render_latex.UserConfig
function M.setup(opts)
  local compat = require("render_latex.compat").summary()
  if not compat.supported then
    require("render_latex.util").warn(
      "render-latex.nvim disabled: missing Neovim features: " .. table.concat(compat.missing, ", ")
    )
    return
  end
  local Config = require("render_latex.config")
  Config.setup(opts)
  M.did_setup = true
  local install_ready = false
  local queue_after_install
  require("render_latex.install").ensure_installed_async(function(path)
    if path == nil then
      return
    end
    if queue_after_install ~= nil then
      queue_after_install()
    else
      install_ready = true
    end
  end)
  if Config.tmux.install_cleanup_hooks then
    require("render_latex.tmux").install_cleanup_hooks()
  end
  queue_after_install = register_autocmds()
  if install_ready then
    queue_after_install()
  end
end

function M.enable()
  require("render_latex.config").set_enabled(true)
  local Renderer = require("render_latex.renderer")
  Renderer.attach(vim.api.nvim_get_current_buf())
  Renderer.queue(vim.api.nvim_get_current_buf())
end

function M.disable()
  local Renderer = require("render_latex.renderer")
  require("render_latex.config").set_enabled(false)
  Renderer.detach(vim.api.nvim_get_current_buf())
end

function M.toggle()
  if require("render_latex.config").enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.refresh()
  require("render_latex.renderer").queue(vim.api.nvim_get_current_buf())
end

function M.status()
  local status = require("render_latex.worker").status()
  status.render = require("render_latex.renderer").resolved_options()
  status.image_backend = require("render_latex.image_backend").status()
  status.suppression = require("render_latex.renderer").suppression_status()
  status.integrations = require("render_latex.integrations").status(vim.api.nvim_get_current_buf())
  require("render_latex.util").info(vim.inspect(status))
  return status
end

function M.doctor_lines()
  local Config = require("render_latex.config")
  local Compat = require("render_latex.compat")
  local ImageBackend = require("render_latex.image_backend")
  local Install = require("render_latex.install")
  local Integrations = require("render_latex.integrations")
  local Renderer = require("render_latex.renderer")
  local Worker = require("render_latex.worker")

  local bufnr = vim.api.nvim_get_current_buf()
  local compat = Compat.summary()
  local backend = ImageBackend.status()
  local worker = Worker.status()
  local install = Install.status()
  local integrations = Integrations.status(bufnr)
  local render = Renderer.resolved_options()
  local suppression = Renderer.suppression_status()
  local filetype = vim.bo[bufnr].filetype

  local lines = {
    "# render-latex doctor",
    "",
    "## Core",
    "",
    "enabled: " .. tostring(Config.enabled),
    "current filetype: " .. (filetype ~= "" and filetype or "<none>"),
    "filetype supported: " .. tostring(Config.is_filetype_supported(filetype)),
    "required Neovim APIs: " .. (compat.supported and "ok" or "missing"),
  }

  if not compat.supported then
    lines[#lines + 1] = "missing APIs: " .. table.concat(compat.missing, ", ")
  end

  vim.list_extend(lines, {
    "",
    "## Rendering",
    "",
    "image backend: " .. backend.name,
    "image backend available: " .. tostring(backend.available),
    "image backend reason: " .. tostring(backend.reason or "<none>"),
    "vim.ui.img available: " .. tostring(backend.builtin_available),
    "kitty available: " .. tostring(backend.kitty_available),
    "tmux detected: " .. tostring(backend.tmux),
    "foreground: "
      .. tostring(render.foreground)
      .. " ("
      .. tostring(render.foreground_source)
      .. ")",
    "font size: " .. tostring(render.font_size),
    "hide on cmdline: " .. tostring(Config.render.hide_on_cmdline),
    "conceallevel: " .. tostring(vim.wo.conceallevel),
    "concealcursor: " .. tostring(vim.wo.concealcursor),
    "suppressed by cmdline: " .. tostring(suppression.cmdline),
    "suppressed by popups/floating windows: " .. tostring(suppression.floating),
    "",
    "## Worker",
    "",
    "running: " .. tostring(worker.running),
    "pending requests: " .. tostring(worker.pending),
    "worker binary: " .. (install.path or "<not found>"),
    "worker source: " .. install.source,
    "detected platform: " .. tostring(install.system or "<unsupported>"),
    "install repository: " .. install.repository,
    "install version: " .. install.version,
    "installing: " .. tostring(install.installing),
  })

  if install.last_error ~= nil then
    lines[#lines + 1] = "last install error: " .. install.last_error
  end

  if install.path == nil then
    lines[#lines + 1] =
      "recommendation: run :RenderLatex install, :RenderLatex build, or configure worker.bin"
  end

  local render_markdown = integrations.render_markdown
  vim.list_extend(lines, {
    "",
    "## render-markdown.nvim",
    "",
    "loaded: " .. tostring(render_markdown.loaded),
    "inspectable: " .. tostring(render_markdown.inspectable),
  })
  if render_markdown.enabled ~= nil then
    lines[#lines + 1] = "enabled: " .. tostring(render_markdown.enabled)
  end
  if render_markdown.latex_enabled ~= nil then
    lines[#lines + 1] = "latex enabled: " .. tostring(render_markdown.latex_enabled)
  end
  lines[#lines + 1] = "conflict: " .. tostring(render_markdown.conflict)
  lines[#lines + 1] = "recommendation: " .. tostring(render_markdown.recommendation)

  local obsidian = integrations.obsidian
  vim.list_extend(lines, {
    "",
    "## obsidian.nvim",
    "",
    "loaded: " .. tostring(obsidian.loaded),
    "workspace: " .. tostring(obsidian.workspace or "<unknown>"),
    "recommendation: " .. tostring(obsidian.recommendation),
    "",
    "## Notes",
    "",
    "Compatibility checks run only in status, health, and doctor commands.",
    "The render loop does not inspect other plugins.",
  })

  if Config.render.inline ~= false and vim.wo.conceallevel == 0 then
    lines[#lines + 1] = "Set conceallevel=2 for the best inline math fallback experience."
  end

  return lines
end

function M.doctor()
  return require("render_latex.util").open_scratch(M.doctor_lines(), "markdown")
end

function M.tmux_setup()
  local Util = require("render_latex.util")
  local lines = {
    "render-latex tmux setup",
    "",
    "Session-local cleanup hooks are opt-in via tmux.install_cleanup_hooks = true.",
    "Add these lines to ~/.tmux.conf if you want global fallback hooks:",
    "",
    "set -g allow-passthrough on",
    "set -g focus-events on",
    'set -g default-terminal "tmux-256color"',
    [[set-hook -g session-window-changed 'run-shell "printf '\033_Ga=d,d=A\033\\' > #{client_tty}"']],
    [[set-hook -g client-session-changed 'run-shell "printf '\033_Ga=d,d=A\033\\' > #{client_tty}"']],
    [[set-hook -g window-pane-changed 'run-shell "printf '\033_Ga=d,d=A\033\\' > #{client_tty}"']],
    "",
    "Then reload tmux with: tmux source-file ~/.tmux.conf",
  }

  Util.open_scratch(lines, "tmux")
end

function M.tmux_check()
  local Util = require("render_latex.util")
  local backend = require("render_latex.image_backend").status()
  local Tmux = require("render_latex.tmux")
  local lines = {
    "render-latex tmux diagnostics",
    "",
    "tmux detected: " .. tostring(backend.tmux),
    "backend: " .. backend.name,
    "builtin vim.ui.img: " .. tostring(backend.builtin_available),
    "TERM: " .. (vim.env.TERM or ""),
  }

  local function append_tmux_option(option)
    lines[#lines + 1] = option .. ": " .. (Tmux.option(option) or "<unavailable>")
  end

  if backend.tmux then
    append_tmux_option("allow-passthrough")
    append_tmux_option("focus-events")
    append_tmux_option("default-terminal")
    lines[#lines + 1] = ""
    local function append_hook_status(label, global)
      lines[#lines + 1] = label .. " cleanup hook status:"
      for _, hook in ipairs(Tmux.hook_status(global)) do
        local state = hook.valid and "ok"
          or (hook.present and "present but mismatched" or "missing")
        lines[#lines + 1] = ("- %s: %s"):format(hook.name, state)
      end
    end

    append_hook_status("session", false)
    lines[#lines + 1] = ""
    append_hook_status("global", true)

    local session_hooks_ok = true
    for _, hook in ipairs(Tmux.hook_status(false)) do
      if not hook.valid then
        session_hooks_ok = false
        break
      end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = session_hooks_ok and "session cleanup hooks are active"
      or "session cleanup hooks failed to install; try :RenderLatex tmux_setup for global hooks"
  end

  Util.open_scratch(lines, "markdown")
end

function M.equation_debug()
  local Util = require("render_latex.util")
  local debug_info, err = require("render_latex.renderer").debug_current()
  if debug_info == nil then
    Util.warn(err or "cursor is not inside a display equation")
    return nil
  end
  Util.info(vim.inspect(debug_info))
  return debug_info
end

function M.equation_rerender()
  local Util = require("render_latex.util")
  local ok, result = require("render_latex.renderer").rerender_current()
  if not ok then
    Util.warn(type(result) == "string" and result or "unable to rerender current equation")
    return false
  end
  Util.info("Queued rerender for current equation")
  return true
end

function M.equation_toggle()
  local Util = require("render_latex.util")
  local ok, result = require("render_latex.renderer").toggle_current()
  if not ok then
    Util.warn(type(result) == "string" and result or "unable to toggle current equation")
    return false
  end
  Util.info(
    result and "Current equation forced to raw mode" or "Current equation returned to rendered mode"
  )
  return true
end

function M.equation_source()
  local Util = require("render_latex.util")
  local source, err = require("render_latex.renderer").current_equation_source()
  if source == nil then
    Util.warn(err or "cursor is not inside a display equation")
    return nil
  end

  local lines = {
    "# Current Equation Source",
    "",
    "```latex",
  }
  vim.list_extend(lines, source.lines)
  vim.list_extend(lines, {
    "```",
    "",
    "Normalized text:",
    "```latex",
    source.equation.text,
    "```",
  })
  Util.open_scratch(lines, "markdown")
  return source
end

return M
