local M = {}

local function module_loaded(name)
  return package.loaded[name] ~= nil
end

local function safe_require(name)
  local ok, module = pcall(require, name)
  if ok then
    return module
  end
  return nil
end

local function render_markdown_status(bufnr)
  local status = {
    loaded = module_loaded("render-markdown"),
    enabled = nil,
    latex_enabled = nil,
    inspectable = false,
    conflict = false,
    status = nil,
    action = nil,
  }

  if not status.loaded then
    status.status = "not loaded"
    return status
  end

  local state = safe_require("render-markdown.state")
  if type(state) ~= "table" then
    status.status = "loaded but not inspectable"
    status.action = "if math rendering overlaps, set render-markdown latex.enabled=false"
    return status
  end

  status.inspectable = true
  status.enabled = state.enabled

  if type(state.get) == "function" then
    local config_ok, config = pcall(state.get, bufnr or vim.api.nvim_get_current_buf())
    if config_ok and type(config) == "table" and type(config.latex) == "table" then
      status.latex_enabled = config.latex.enabled
    end
  end

  status.conflict = status.latex_enabled ~= false
  if status.conflict then
    status.status = "conflict detected"
    status.action = "set render-markdown latex.enabled=false"
  else
    status.status = "compatible; render-markdown LaTeX rendering is disabled"
  end

  return status
end

local function obsidian_status(bufnr)
  local status = {
    loaded = module_loaded("obsidian"),
    client_available = false,
    workspace = nil,
    status = nil,
    action = nil,
  }

  if not status.loaded then
    status.status = "not loaded"
    return status
  end

  local obsidian = safe_require("obsidian")
  if type(obsidian) ~= "table" then
    status.status = "loaded but not inspectable; no special render-latex config is required"
    return status
  end

  if type(obsidian.workspace) == "table" then
    status.client_available = true
    status.workspace = obsidian.workspace.name or obsidian.workspace.path
    status.status = "compatible; no special render-latex config is required"
    return status
  elseif type(obsidian.workspace) == "string" then
    status.client_available = true
    status.workspace = obsidian.workspace
    status.status = "compatible; no special render-latex config is required"
    return status
  end

  status.status = "compatible; no special render-latex config is required"
  return status
end

function M.status(bufnr)
  return {
    render_markdown = render_markdown_status(bufnr),
    obsidian = obsidian_status(bufnr),
  }
end

function M.render_markdown_conflict(bufnr)
  local status = render_markdown_status(bufnr)
  return status.loaded and status.conflict, status
end

function M.obsidian(bufnr)
  return obsidian_status(bufnr)
end

return M
