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
    loaded = module_loaded("render-markdown") or module_loaded("render-markdown.state"),
    global_enabled = nil,
    buffer_enabled = nil,
    latex_enabled = nil,
    inspectable = false,
    conflict = false,
    render_latex_active = false,
    status = nil,
    action = nil,
  }

  if not status.loaded then
    status.status = "not loaded"
    return status
  end

  local config = require("render_latex.config")
  status.render_latex_active = config.enabled
    and require("render_latex.sources").supports(bufnr or vim.api.nvim_get_current_buf())

  local state = safe_require("render-markdown.state")
  if type(state) ~= "table" then
    status.status = "loaded but not inspectable"
    status.conflict = status.render_latex_active
    if status.render_latex_active then
      status.action = "if math rendering overlaps, set render-markdown latex.enabled=false"
    end
    return status
  end

  status.inspectable = true
  status.global_enabled = state.enabled

  if type(state.get) == "function" then
    local config_ok, config = pcall(state.get, bufnr or vim.api.nvim_get_current_buf())
    if config_ok and type(config) == "table" then
      if type(config.enabled) == "boolean" then
        status.buffer_enabled = config.enabled
      end
      if type(config.latex) == "table" then
        status.latex_enabled = config.latex.enabled
      end
    end
  end

  local render_markdown_active = status.global_enabled ~= false and status.buffer_enabled ~= false
  status.conflict = status.render_latex_active
    and render_markdown_active
    and status.latex_enabled ~= false
  if not status.render_latex_active then
    status.status = "render-latex inactive for this buffer"
  elseif not render_markdown_active then
    status.status = "render-markdown disabled for this buffer"
  elseif status.latex_enabled == false then
    status.status = "compatible; render-markdown LaTeX rendering is disabled"
  elseif status.latex_enabled == true then
    status.status = "conflict detected"
    status.action = "set render-markdown latex.enabled=false"
  else
    status.status = "loaded; LaTeX setting unknown"
    status.action = "if math rendering overlaps, set render-markdown latex.enabled=false"
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
    jupynvim = require("render_latex.integrations.jupynvim").status(bufnr),
  }
end

function M.render_markdown_conflict(bufnr)
  local status = render_markdown_status(bufnr)
  return status.loaded and status.conflict, status
end

---Redraws render-markdown.nvim in `bufnr` after the inline math marks changed. Versions that read
---the extmarks of other plugins then measure table cells with the concealed math, and draw wrapped
---table rows with it instead of the raw LaTeX.
---@param bufnr integer
function M.refresh_render_markdown(bufnr)
  if not module_loaded("render-markdown") or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  -- Only buffers render-markdown is drawing: render() would attach it to any other buffer.
  local ns = vim.api.nvim_get_namespaces()["render-markdown.nvim"]
  if ns == nil or #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { limit = 1 }) == 0 then
    return
  end
  local render_markdown = safe_require("render-markdown")
  if type(render_markdown) == "table" and type(render_markdown.render) == "function" then
    pcall(render_markdown.render, { buf = bufnr })
  end
end

function M.obsidian(bufnr)
  return obsidian_status(bufnr)
end

function M.jupynvim(bufnr)
  return require("render_latex.integrations.jupynvim").status(bufnr)
end

return M
