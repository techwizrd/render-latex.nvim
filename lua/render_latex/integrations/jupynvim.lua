local M = {}

local function enabled()
  return require("render_latex.config").integrations.jupynvim.enabled
end

local function notebook_module()
  local ok, notebook = pcall(require, "jupynvim.notebook")
  if ok and type(notebook) == "table" then
    return notebook
  end
  return nil
end

function M.notebook(bufnr)
  local notebook = notebook_module()
  if notebook == nil or type(notebook.get) ~= "function" then
    return nil
  end

  local ok, nb = pcall(notebook.get, bufnr)
  if ok then
    return nb
  end
  return nil
end

local function cell_segments(bufnr, sep)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local segments = {}
  local start_row = 0

  for index, line in ipairs(lines) do
    if line == sep then
      segments[#segments + 1] = { start_row = start_row, end_row = index - 2 }
      start_row = index
    end
  end
  segments[#segments + 1] = { start_row = start_row, end_row = #lines - 1 }

  return segments
end

function M.markdown_ranges(bufnr)
  local notebook = notebook_module()
  local nb = notebook ~= nil and M.notebook(bufnr) or nil
  if notebook == nil or nb == nil or type(nb.cells) ~= "table" then
    return {}
  end

  local sep = notebook.CELL_SEP
  if type(sep) ~= "string" or sep == "" then
    return {}
  end

  local segments = cell_segments(bufnr, sep)

  if #segments ~= #nb.cells then
    return {}
  end

  local ranges = {}
  for index, segment in ipairs(segments) do
    local cell = nb.cells[index]
    if cell ~= nil and cell.cell_type == "markdown" and segment.start_row <= segment.end_row then
      ranges[#ranges + 1] = segment
    end
  end

  return ranges
end

local function range_diagnostics(bufnr, notebook, nb)
  if notebook == nil or nb == nil or type(nb.cells) ~= "table" then
    return {
      cell_count = 0,
      segment_count = 0,
      range_valid = false,
      range_warning = nil,
    }
  end

  local sep = notebook.CELL_SEP
  if type(sep) ~= "string" or sep == "" then
    return {
      cell_count = #nb.cells,
      segment_count = 0,
      range_valid = false,
      range_warning = "jupynvim CELL_SEP is unavailable",
    }
  end

  local segments = cell_segments(bufnr, sep)
  local valid = #segments == #nb.cells
  return {
    cell_count = #nb.cells,
    segment_count = #segments,
    range_valid = valid,
    range_warning = not valid
        and "jupynvim cell metadata and buffer separators disagree; rendering is disabled for safety"
      or nil,
  }
end

function M.revision(bufnr)
  local notebook = notebook_module()
  local nb = notebook ~= nil and M.notebook(bufnr) or nil
  if notebook == nil or nb == nil or type(nb.cells) ~= "table" then
    return nil
  end

  local sep = notebook.CELL_SEP
  if type(sep) ~= "string" or sep == "" then
    return nil
  end

  local parts = { tostring(#nb.cells) }
  for index, cell in ipairs(nb.cells) do
    parts[#parts + 1] = tostring(index)
    parts[#parts + 1] = type(cell) == "table" and tostring(cell.cell_type) or "nil"
  end

  return table.concat(parts, ":")
end

local function signcolumn_width(winid)
  local value = vim.api.nvim_get_option_value("signcolumn", { win = winid })
  if type(value) ~= "string" then
    return 0
  end
  local count = value:match("^yes:(%d+)$") or value:match("^auto:(%d+)$")
  if count ~= nil then
    return 2 * tonumber(count)
  end
  if value == "yes" or value == "auto" then
    return 2
  end
  return 0
end

local function numbercolumn_width(bufnr, winid)
  local number = vim.api.nvim_get_option_value("number", { win = winid })
  local relativenumber = vim.api.nvim_get_option_value("relativenumber", { win = winid })
  if not number and not relativenumber then
    return 0
  end
  local numberwidth = vim.api.nvim_get_option_value("numberwidth", { win = winid })
  local min_width = type(numberwidth) == "number" and numberwidth or 4
  return math.max(min_width, #tostring(vim.api.nvim_buf_line_count(bufnr)) + 1)
end

local function foldcolumn_width(winid)
  local value = vim.api.nvim_get_option_value("foldcolumn", { win = winid })
  if type(value) ~= "string" then
    return 0
  end
  local count = value:match("^auto:(%d+)$") or value:match("^(%d+)$")
  if count ~= nil then
    return tonumber(count)
  end
  if value == "auto" then
    return 1
  end
  return 0
end

function M.image_bounds(bufnr, winid, window, position)
  local text_width = math.max(
    40,
    window.width
      - signcolumn_width(winid)
      - numbercolumn_width(bufnr, winid)
      - foldcolumn_width(winid)
  )
  local border_width = 2
  return {
    start_col = position.col + border_width,
    width = math.max(1, text_width - border_width * 2),
  }
end

function M.status(bufnr)
  local loaded = package.loaded["jupynvim"] ~= nil or package.loaded["jupynvim.notebook"] ~= nil
  if not enabled() then
    return {
      enabled = false,
      loaded = loaded,
      notebook = false,
      cell_count = 0,
      segment_count = 0,
      range_valid = false,
      range_warning = nil,
      markdown_ranges = 0,
      experimental = true,
    }
  end

  local notebook = notebook_module()
  local nb = M.notebook(bufnr)
  local diagnostics = range_diagnostics(bufnr, notebook, nb)
  local ranges = nb ~= nil and diagnostics.range_valid and M.markdown_ranges(bufnr) or {}
  return {
    enabled = enabled(),
    loaded = loaded,
    notebook = nb ~= nil,
    cell_count = diagnostics.cell_count,
    segment_count = diagnostics.segment_count,
    range_valid = diagnostics.range_valid,
    range_warning = diagnostics.range_warning,
    markdown_ranges = #ranges,
    experimental = true,
  }
end

return M
