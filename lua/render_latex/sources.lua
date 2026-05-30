local Config = require("render_latex.config")
local Detect = require("render_latex.detect")

local M = {}

local user_sources = {}

local markdown_source = {
  name = "markdown",
  incremental = true,
  attach = function(bufnr)
    return Config.is_filetype_supported(vim.bo[bufnr].filetype)
  end,
  display_equations = function(bufnr)
    return Detect.scan(bufnr)
  end,
  inline = true,
}

local jupynvim_source = {
  name = "jupynvim",
  experimental = true,
  incremental = false,
  suppress_default_equation_labels = true,
  clear_source_line_background = true,
  attach = function(bufnr)
    return Config.integrations.jupynvim.enabled
      and require("render_latex.integrations.jupynvim").notebook(bufnr) ~= nil
  end,
  display_ranges = function(bufnr)
    return require("render_latex.integrations.jupynvim").markdown_ranges(bufnr)
  end,
  revision = function(bufnr)
    return require("render_latex.integrations.jupynvim").revision(bufnr)
  end,
  image_bounds = function(bufnr, winid, window, position)
    return require("render_latex.integrations.jupynvim").image_bounds(
      bufnr,
      winid,
      window,
      position
    )
  end,
  inline = false,
}

local builtin_sources = {
  jupynvim_source,
  markdown_source,
}

local function valid_source(source)
  return type(source) == "table"
    and type(source.name) == "string"
    and type(source.attach) == "function"
end

local function source_attaches(source, bufnr)
  local ok, attached = pcall(source.attach, bufnr)
  return ok and attached == true
end

function M.register(source)
  vim.validate({
    source = { source, "table" },
    ["source.name"] = { source.name, "string" },
    ["source.attach"] = { source.attach, "function" },
  })

  user_sources[#user_sources + 1] = source
end

function M.resolve(bufnr)
  for index = #user_sources, 1, -1 do
    local source = user_sources[index]
    if valid_source(source) and source_attaches(source, bufnr) then
      return source
    end
  end

  for _, source in ipairs(builtin_sources) do
    if source_attaches(source, bufnr) then
      return source
    end
  end

  return nil
end

function M.supports(bufnr)
  return M.resolve(bufnr) ~= nil
end

function M.display_equations(bufnr)
  local source = M.resolve(bufnr)
  if source == nil then
    return {}
  end
  if type(source.display_equations) == "function" then
    local ok, equations = pcall(source.display_equations, bufnr)
    return ok and equations or {}
  end
  if type(source.display_ranges) == "function" then
    local ok, ranges = pcall(source.display_ranges, bufnr)
    if ok and type(ranges) == "table" then
      return Detect.scan_ranges(bufnr, ranges)
    end
    return {}
  end
  return Detect.scan(bufnr)
end

function M.inline_ranges(bufnr, visible_ranges)
  local source = M.resolve(bufnr)
  if source == nil then
    return {}
  end
  if source.inline == false then
    return {}
  end
  if type(source.inline_ranges) == "function" then
    local ok, ranges = pcall(source.inline_ranges, bufnr, visible_ranges)
    if ok and type(ranges) == "table" then
      return ranges
    end
    return {}
  end
  return visible_ranges
end

function M.status(bufnr)
  local source = M.resolve(bufnr)
  return {
    active = source and source.name or nil,
    experimental = source and source.experimental == true or false,
  }
end

function M.incremental(bufnr)
  local source = M.resolve(bufnr)
  return source ~= nil and source.incremental ~= false
end

function M.revision(bufnr)
  local source = M.resolve(bufnr)
  if source ~= nil and type(source.revision) == "function" then
    local ok, revision = pcall(source.revision, bufnr)
    if
      ok
      and (type(revision) == "string" or type(revision) == "number" or type(revision) == "boolean")
    then
      return tostring(revision)
    end
  end
  return nil
end

function M.render_context(bufnr)
  local source = M.resolve(bufnr)
  return {
    name = source and source.name or nil,
    suppress_default_equation_labels = source and source.suppress_default_equation_labels == true
      or false,
    clear_source_line_background = source and source.clear_source_line_background == true or false,
  }
end

function M.image_bounds(bufnr, winid, window, position)
  local source = M.resolve(bufnr)
  if source ~= nil and type(source.image_bounds) == "function" then
    local ok, bounds = pcall(source.image_bounds, bufnr, winid, window, position)
    if ok and type(bounds) == "table" then
      return bounds
    end
  end
  return {
    start_col = position.col,
    width = window.width,
  }
end

return M
