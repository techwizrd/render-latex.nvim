---@class render_latex.WorkerOptions
---@field bin? string
---@field args string[]

---@class render_latex.InstallOptions
---@field auto boolean
---@field repository string
---@field version string

---@class render_latex.RenderOptions
---@field foreground? string
---@field match_text_color boolean
---@field background string
---@field match_text_size boolean
---@field preset 'match_text'|'compact'|'presentation'
---@field font_size number
---@field text_scale number
---@field exit_delay_ms integer
---@field placeholder boolean
---@field equation_labels false|'right'|'sign'|'both'
---@field equation_label_format string
---@field padding number
---@field scale number
---@field inline false|'conceal'|'content'|'highlight'
---@field inline_symbols boolean
---@field hide_on_cmdline boolean

---@class render_latex.ImageOptions
---@field backend 'auto'|'nvim'|'kitty'
---@field zindex integer
---@field cell_width_px number
---@field cell_height_px number

---@class render_latex.TmuxOptions
---@field install_cleanup_hooks boolean

---@class render_latex.IntegrationOptions
---@field jupynvim { enabled: boolean }

---@class render_latex.UserConfig
---@field enabled boolean
---@field debounce integer
---@field file_types string[]
---@field render_modes string[]
---@field prefetch_lines integer
---@field conceal boolean
---@field max_file_lines integer
---@field worker render_latex.WorkerOptions
---@field install render_latex.InstallOptions
---@field render render_latex.RenderOptions
---@field image render_latex.ImageOptions
---@field tmux render_latex.TmuxOptions
---@field integrations render_latex.IntegrationOptions

---@class render_latex.Config: render_latex.UserConfig
---@field augroup integer
---@field ns integer
local M = {}

local defaults = {
  enabled = true,
  debounce = 75,
  file_types = { "markdown" },
  render_modes = { "n", "i" },
  prefetch_lines = 40,
  conceal = true,
  max_file_lines = 5000,
  worker = {
    bin = nil,
    args = {},
  },
  install = {
    auto = true,
    repository = "techwizrd/render-latex.nvim",
    version = "latest",
  },
  render = {
    foreground = nil,
    match_text_color = true,
    background = "transparent",
    match_text_size = true,
    preset = "match_text",
    font_size = 34,
    text_scale = 1.0,
    exit_delay_ms = 150,
    placeholder = true,
    equation_labels = "right",
    equation_label_format = "Eq. %d",
    padding = 10,
    scale = 1.5,
    inline = "conceal",
    inline_symbols = true,
    hide_on_cmdline = false,
  },
  image = {
    backend = "auto",
    zindex = 60,
    cell_width_px = 10,
    cell_height_px = 20,
  },
  tmux = {
    install_cleanup_hooks = false,
  },
  integrations = {
    jupynvim = {
      enabled = true,
    },
  },
}

local config = vim.deepcopy(defaults)
local explicit = {}

local function collect_explicit(opts, prefix, result)
  for key, value in pairs(opts or {}) do
    local path = prefix ~= "" and (prefix .. "." .. key) or key
    result[path] = true
    if type(value) == "table" then
      collect_explicit(value, path, result)
    end
  end
end

local function validate_enum(name, value, allowed)
  if not vim.tbl_contains(allowed, value) then
    error(("%s must be one of: %s"):format(name, table.concat(allowed, ", ")), 3)
  end
end

local function validate_positive(name, value)
  if type(value) ~= "number" or value <= 0 then
    error(("%s must be a positive number"):format(name), 3)
  end
end

local function validate_nonnegative(name, value)
  if type(value) ~= "number" or value < 0 then
    error(("%s must be a non-negative number"):format(name), 3)
  end
end

M.augroup = vim.api.nvim_create_augroup("render-latex", { clear = true })
M.ns = vim.api.nvim_create_namespace("render-latex")

setmetatable(M, {
  __index = function(_, key)
    return config[key]
  end,
})

---@param opts? render_latex.UserConfig
function M.setup(opts)
  explicit = {}
  collect_explicit(opts or {}, "", explicit)
  config = vim.tbl_deep_extend("force", {}, vim.deepcopy(defaults), opts or {})

  vim.validate({
    enabled = { config.enabled, "boolean" },
    debounce = { config.debounce, "number" },
    file_types = { config.file_types, "table" },
    render_modes = { config.render_modes, "table" },
    prefetch_lines = { config.prefetch_lines, "number" },
    conceal = { config.conceal, "boolean" },
    max_file_lines = { config.max_file_lines, "number" },
    worker = { config.worker, "table" },
    install = { config.install, "table" },
    render = { config.render, "table" },
    image = { config.image, "table" },
    tmux = { config.tmux, "table" },
    integrations = { config.integrations, "table" },
  })

  vim.validate({
    ["worker.args"] = { config.worker.args, "table" },
    ["install.auto"] = { config.install.auto, "boolean" },
    ["install.repository"] = { config.install.repository, "string" },
    ["install.version"] = { config.install.version, "string" },
    ["render.match_text_color"] = { config.render.match_text_color, "boolean" },
    ["render.match_text_size"] = { config.render.match_text_size, "boolean" },
    ["render.placeholder"] = { config.render.placeholder, "boolean" },
    ["render.inline_symbols"] = { config.render.inline_symbols, "boolean" },
    ["render.hide_on_cmdline"] = { config.render.hide_on_cmdline, "boolean" },
    ["render.background"] = { config.render.background, "string" },
    ["render.equation_label_format"] = { config.render.equation_label_format, "string" },
    ["tmux.install_cleanup_hooks"] = { config.tmux.install_cleanup_hooks, "boolean" },
    ["integrations.jupynvim"] = { config.integrations.jupynvim, "table" },
    ["integrations.jupynvim.enabled"] = {
      config.integrations.jupynvim.enabled,
      "boolean",
    },
  })

  if config.worker.bin ~= nil then
    vim.validate({ ["worker.bin"] = { config.worker.bin, "string" } })
  end
  if config.render.foreground ~= nil then
    vim.validate({ ["render.foreground"] = { config.render.foreground, "string" } })
  end

  validate_enum("render.preset", config.render.preset, { "match_text", "compact", "presentation" })
  validate_enum("image.backend", config.image.backend, { "auto", "nvim", "kitty" })
  if config.render.inline ~= false then
    validate_enum("render.inline", config.render.inline, { "conceal", "content", "highlight" })
  end
  if config.render.equation_labels ~= false then
    validate_enum(
      "render.equation_labels",
      config.render.equation_labels,
      { "right", "sign", "both" }
    )
  end

  validate_nonnegative("debounce", config.debounce)
  validate_nonnegative("prefetch_lines", config.prefetch_lines)
  validate_positive("max_file_lines", config.max_file_lines)
  validate_positive("render.font_size", config.render.font_size)
  validate_positive("render.text_scale", config.render.text_scale)
  validate_nonnegative("render.exit_delay_ms", config.render.exit_delay_ms)
  validate_nonnegative("render.padding", config.render.padding)
  validate_positive("render.scale", config.render.scale)
  validate_nonnegative("image.zindex", config.image.zindex)
  validate_positive("image.cell_width_px", config.image.cell_width_px)
  validate_positive("image.cell_height_px", config.image.cell_height_px)
end

function M.values()
  return vim.deepcopy(config)
end

function M.is_explicit(path)
  return explicit[path] == true
end

---@param enabled boolean
function M.set_enabled(enabled)
  config.enabled = enabled
end

function M.is_filetype_supported(filetype)
  return vim.tbl_contains(config.file_types, filetype)
end

function M.should_render_mode(mode)
  return vim.tbl_contains(config.render_modes, mode)
end

return M
