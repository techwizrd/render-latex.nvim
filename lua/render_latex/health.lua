local Config = require("render_latex.config")
local Compat = require("render_latex.compat")
local ImageBackend = require("render_latex.image_backend")
local Install = require("render_latex.install")
local Integrations = require("render_latex.integrations")
local Tmux = require("render_latex.tmux")

local M = {}

function M.check()
  vim.health.start("render-latex.nvim")

  local compat = Compat.summary()
  if compat.supported then
    vim.health.ok("required Neovim APIs are available")
  else
    vim.health.error("missing required Neovim APIs: " .. table.concat(compat.missing, ", "))
  end

  if vim.ui.img == nil or type(vim.ui.img.set) ~= "function" then
    vim.health.info(
      "vim.ui.img is unavailable; render-latex can still use Kitty graphics when supported"
    )
  else
    vim.health.ok("vim.ui.img API is available")
  end

  local backend = ImageBackend.status()
  if backend.available then
    vim.health.ok("image backend: " .. backend.name)
  elseif backend.kitty_probing then
    vim.health.info("image backend: probing Kitty graphics support; rerun health shortly")
  else
    vim.health.warn("image backend unavailable: " .. (backend.reason or backend.name))
  end
  if backend.tmux and backend.available and backend.name == "kitty" then
    vim.health.warn("tmux detected; render-latex is using Kitty passthrough wrapping")
  elseif backend.tmux then
    vim.health.info("tmux detected")
  end

  if backend.tmux and vim.fn.executable("tmux") == 1 then
    local value = Tmux.option("allow-passthrough")
    if value ~= "on" and value ~= "all" then
      vim.health.warn("tmux allow-passthrough is not enabled; set `set -g allow-passthrough on`")
    else
      vim.health.ok("tmux allow-passthrough is enabled")
    end

    local focus_value = Tmux.option("focus-events")
    if focus_value ~= "on" and focus_value ~= "all" then
      vim.health.warn(
        "tmux focus-events is not enabled; cleanup on tmux window switches may be delayed"
      )
    else
      vim.health.ok("tmux focus-events is enabled")
    end

    local hooks = Tmux.hook_status(false)
    local missing = {}
    for _, hook in ipairs(hooks) do
      if not hook.valid then
        missing[#missing + 1] = hook.name
      end
    end
    if #missing > 0 then
      vim.health.warn(
        "tmux session cleanup hooks missing or incomplete: " .. table.concat(missing, ", ")
      )
    else
      vim.health.ok("tmux session cleanup hooks are installed")
    end

    if Config.tmux.install_cleanup_hooks then
      vim.health.info("tmux session cleanup hooks are configured for automatic installation")
    else
      vim.health.info(
        "tmux cleanup hooks are opt-in; run :RenderLatex tmux_setup for setup details"
      )
    end
  end

  local install = Install.status()
  vim.health.info("detected platform: " .. tostring(install.system or "<unsupported>"))
  vim.health.info("install source: " .. install.repository .. " (" .. install.version .. ")")
  if install.path_error ~= nil then
    vim.health.warn(install.path_error)
  elseif install.installing then
    vim.health.info("worker binary is being installed in the background")
  elseif install.building then
    vim.health.info("worker binary is being built in the background")
  elseif install.path == nil then
    vim.health.warn(
      "worker binary not found. Run :RenderLatex install, :RenderLatex build, or configure worker.bin."
    )
  else
    vim.health.ok("worker binary found at " .. install.path .. " (" .. install.source .. ")")
  end
  if install.last_error ~= nil then
    vim.health.warn("last worker install error: " .. install.last_error)
  end

  if Config.render.inline ~= false and vim.wo.conceallevel == 0 then
    vim.health.warn("inline math fallback is enabled but conceallevel is 0; set conceallevel=2")
  elseif Config.render.inline ~= false then
    vim.health.ok("inline math fallback conceal settings are usable")
  end

  local render_markdown_conflict, render_markdown =
    Integrations.render_markdown_conflict(vim.api.nvim_get_current_buf())
  if render_markdown.loaded then
    if render_markdown_conflict then
      if render_markdown.inspectable then
        vim.health.warn(
          "render-markdown.nvim is loaded with LaTeX rendering enabled; set `latex = { enabled = false }` in render-markdown.nvim"
        )
      else
        vim.health.info(
          "render-markdown.nvim is loaded but not inspectable; if math rendering overlaps, set `latex = { enabled = false }`"
        )
      end
    else
      vim.health.ok("render-markdown.nvim loaded with LaTeX rendering disabled")
    end
  else
    vim.health.info("render-markdown.nvim is not loaded")
  end

  local obsidian = Integrations.obsidian(vim.api.nvim_get_current_buf())
  if obsidian.loaded then
    local suffix = obsidian.workspace ~= nil and (" for workspace " .. obsidian.workspace) or ""
    vim.health.ok("obsidian.nvim loaded" .. suffix .. "; no special render-latex config required")
  else
    vim.health.info("obsidian.nvim is not loaded")
  end

  local ok, err = pcall(function()
    vim.validate({
      enabled = { Config.enabled, "boolean" },
      debounce = { Config.debounce, "number" },
      max_file_lines = { Config.max_file_lines, "number" },
    })
  end)

  if ok then
    vim.health.ok("configuration is valid")
  else
    vim.health.error("invalid configuration: " .. err)
  end
end

return M
