local Util = require("render_latex.util")

local M = {}
local unpack = table.unpack or unpack

local ok_query, latex_block_query = pcall(
  vim.treesitter.query.parse,
  "markdown_inline",
  [[
  (latex_block) @math
]]
)
if not ok_query then
  latex_block_query = nil
end

local function normalize_text(text)
  local trimmed = vim.trim(text)

  if trimmed:sub(1, 2) == "\\[" and trimmed:sub(-2) == "\\]" then
    local lines = vim.split(trimmed, "\n", { plain = true })
    if #lines >= 2 then
      table.remove(lines, 1)
      table.remove(lines, #lines)
      return vim.trim(table.concat(lines, "\n"))
    end
    return vim.trim(trimmed:sub(3, -3))
  end

  return text
end

local function strip_blockquote_prefix(line)
  local text = line
  while true do
    local next_text = text:match("^%s*>%s?(.*)$")
    if next_text == nil then
      return text
    end
    text = next_text
  end
end

local function is_blockquote_line(line)
  return line:match("^%s*>") ~= nil
end

local function has_blockquote_line(lines)
  for _, line in ipairs(lines) do
    if is_blockquote_line(line) then
      return true
    end
  end
  return false
end

local function math_line(line)
  return vim.trim(strip_blockquote_prefix(line))
end

local function math_block_lines(lines)
  local block = {}
  for _, line in ipairs(lines) do
    block[#block + 1] = strip_blockquote_prefix(line)
  end
  return block
end

local function equation_key(start_row, end_row, text)
  return Util.sha256(("%d:%d:%s"):format(start_row, end_row, text))
end

local function finalize(lines, start_row, end_row, delimiter)
  local text = normalize_text(table.concat(math_block_lines(lines), "\n"))
  return {
    key = equation_key(start_row, end_row, text),
    start_row = start_row,
    end_row = end_row,
    text = text,
    kind = "display",
    delimiter = delimiter,
    quoted = has_blockquote_line(lines),
  }
end

local function finalize_text(text, start_row, end_row, delimiter, quoted)
  local normalized = normalize_text(text)
  return {
    key = equation_key(start_row, end_row, normalized),
    start_row = start_row,
    end_row = end_row,
    text = normalized,
    kind = "display",
    delimiter = delimiter,
    quoted = quoted == true,
  }
end

local function node_text(bufnr, node)
  local start_row, start_col, end_row, end_col = node:range()
  return table.concat(
    vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {}),
    "\n"
  )
end

local function strip_dollar_block(text)
  return vim.trim(text:gsub("^%$%$%s*\n?", ""):gsub("\n?%s*%$%$$", ""))
end

local function display_delimiter(text)
  local trimmed = vim.trim(text)
  if trimmed:sub(1, 2) == "$$" and trimmed:sub(-2) == "$$" then
    return "$$"
  end
  if trimmed:sub(1, 2) == "\\[" and trimmed:sub(-2) == "\\]" then
    return "\\["
  end
  return nil
end

local function fence_marker(line)
  local marker = vim.trim(line):match("^(```+)") or vim.trim(line):match("^(~~~+)")
  if marker == nil then
    return nil
  end
  return marker:sub(1, 1), #marker
end

local function fenced_rows(lines)
  local rows = {}
  local fence_char = nil
  local fence_length = 0

  for index, line in ipairs(lines) do
    local char, length = fence_marker(line)
    if fence_char == nil and char ~= nil then
      rows[index] = true
      fence_char = char
      fence_length = length or 0
    elseif fence_char ~= nil then
      rows[index] = true
      if char == fence_char and length ~= nil and length >= fence_length then
        fence_char = nil
        fence_length = 0
      end
    end
  end

  return rows
end

local function frontmatter_rows(lines)
  local rows = {}
  if vim.trim(lines[1] or "") ~= "---" then
    return rows
  end

  rows[1] = true
  for index = 2, #lines do
    rows[index] = true
    if vim.trim(lines[index]) == "---" then
      break
    end
  end

  return rows
end

local function obsidian_comment_rows(lines)
  local rows = {}
  local in_comment = false

  for index, line in ipairs(lines) do
    local search_col = 1
    while true do
      local start_col = line:find("%%%%", search_col)
      if start_col == nil then
        break
      end
      rows[index] = true
      in_comment = not in_comment
      search_col = start_col + 2
    end
    if in_comment then
      rows[index] = true
    end
  end

  return rows
end

local function indented_code_rows(lines)
  local rows = {}

  for index, line in ipairs(lines) do
    if line:match("^    %S") or line:match("^\t%S") then
      rows[index] = true
    end
  end

  return rows
end

local function ignored_rows(lines)
  local rows = fenced_rows(lines)
  for _, group in ipairs({
    frontmatter_rows(lines),
    obsidian_comment_rows(lines),
    indented_code_rows(lines),
  }) do
    for row in pairs(group) do
      rows[row] = true
    end
  end
  return rows
end

local function pipe_table_delimiter(line)
  local trimmed = vim.trim(line)
  if not trimmed:find("|", 1, true) then
    return false
  end

  trimmed = trimmed:gsub("^|", ""):gsub("|$", "")
  local cells = 0
  for cell in trimmed:gmatch("([^|]+)") do
    cells = cells + 1
    local value = vim.trim(cell)
    if not value:match("^:?-+:?$") or not value:match("---") then
      return false
    end
  end
  return cells > 0
end

local function pipe_table_rows(lines, ignored)
  local rows = {}
  for index, line in ipairs(lines) do
    if not ignored[index] and pipe_table_delimiter(line) then
      local start_index = index - 1
      while start_index >= 1 do
        local current = lines[start_index]
        if ignored[start_index] or not current:find("|", 1, true) then
          break
        end
        rows[start_index] = true
        start_index = start_index - 1
      end

      rows[index] = true
      local end_index = index + 1
      while end_index <= #lines do
        local current = lines[end_index]
        if ignored[end_index] or not current:find("|", 1, true) then
          break
        end
        rows[end_index] = true
        end_index = end_index + 1
      end
    end
  end
  return rows
end

local function scan_context(bufnr, end_row)
  local end_index = -1
  if end_row ~= nil then
    end_index = math.min(vim.api.nvim_buf_line_count(bufnr), end_row + 1)
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, end_index, false)
  local ignored = ignored_rows(lines)
  return {
    lines = lines,
    ignored = ignored,
    table_rows = pipe_table_rows(lines, ignored),
  }
end

local function markdown_inline_parser(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
  if not ok or parser == nil then
    return nil
  end

  local parsed = pcall(function()
    parser:parse(true)
  end)
  if not parsed then
    return nil
  end

  local child = parser:children().markdown_inline
  if child == nil then
    return nil
  end

  parsed = pcall(function()
    child:parse(true)
  end)
  if not parsed then
    return nil
  end

  return child
end

local function treesitter_equations(bufnr, context, start_row, end_row)
  if latex_block_query == nil then
    return {}
  end

  local parser = markdown_inline_parser(bufnr)
  if parser == nil then
    return {}
  end

  local equations = {}
  local ok, trees = pcall(function()
    return parser:parse(true)
  end)
  if not ok then
    return {}
  end

  for _, tree in ipairs(trees) do
    local root = tree:root()
    for _, node in latex_block_query:iter_captures(root, bufnr, start_row, end_row + 1) do
      local success, capture_start, capture_end, text, delimiter, quoted = pcall(function()
        local start_row0, _, end_row0 = node:range()
        local raw_text = node_text(bufnr, node)
        local raw_lines = vim.split(raw_text, "\n", { plain = true })
        raw_text = table.concat(math_block_lines(raw_lines), "\n")
        local delimiter = display_delimiter(raw_text)
        if delimiter == nil then
          return nil
        end
        return start_row0,
          end_row0,
          strip_dollar_block(raw_text),
          delimiter,
          has_blockquote_line(raw_lines)
      end)
      if
        success
        and capture_start ~= nil
        and capture_start >= start_row
        and capture_end <= end_row + 1
        and not context.ignored[capture_start + 1]
      then
        equations[#equations + 1] =
          finalize_text(text, capture_start, capture_end, delimiter, quoted)
      end
    end
  end

  return equations
end

local function bracket_equations(context, start_row, end_row)
  local lines = context.lines
  local equations = {}
  local index = start_row + 1
  local limit = math.min(#lines, end_row + 1)

  while index <= limit do
    if not context.ignored[index] and math_line(lines[index]):match("^\\%[") then
      local block = { lines[index] }
      local block_start = index - 1
      local end_index = index
      local found_end = false
      while end_index < limit do
        if math_line(lines[end_index]):match("\\%]$") then
          found_end = true
          break
        end
        end_index = end_index + 1
        block[#block + 1] = lines[end_index]
      end
      if not found_end and math_line(lines[end_index]):match("\\%]$") then
        found_end = true
      end
      if found_end then
        equations[#equations + 1] = finalize(block, block_start, end_index - 1, "\\[")
      end
      index = end_index
      limit = math.max(limit, math.min(#lines, end_index))
    end

    index = index + 1
  end

  return equations
end

local function dollar_equations(context, start_row, end_row)
  local lines = context.lines
  local equations = {}
  local index = start_row + 1
  local limit = math.min(#lines, end_row + 1)

  while index <= limit do
    local line = lines[index]
    local trimmed = math_line(line)
    if not context.ignored[index] and trimmed:match("^%$%$") then
      local block = { line }
      local block_start = index - 1

      if trimmed ~= "$$" and trimmed:match("%$%$$") and #trimmed > 4 then
        equations[#equations + 1] = finalize(block, block_start, block_start, "$$")
      else
        local end_index = index
        local found_end = false
        while end_index < limit do
          end_index = end_index + 1
          block[#block + 1] = lines[end_index]
          if math_line(lines[end_index]):match("%$%$$") then
            found_end = true
            break
          end
        end
        if found_end then
          equations[#equations + 1] = finalize(block, block_start, end_index - 1, "$$")
        end
        index = end_index
        limit = math.max(limit, math.min(#lines, end_index))
      end
    end

    index = index + 1
  end

  return equations
end

local function merge_unique_equations(...)
  local merged = {}
  local seen = {}

  for _, group in ipairs({ ... }) do
    for _, equation in ipairs(group) do
      local id = string.format("%d:%d", equation.start_row, equation.end_row)
      if not seen[id] then
        seen[id] = true
        merged[#merged + 1] = equation
      end
    end
  end

  return merged
end

local function sort_equations(equations)
  table.sort(equations, function(left, right)
    if left.start_row == right.start_row then
      return left.end_row < right.end_row
    end
    return left.start_row < right.start_row
  end)
  return equations
end

local function is_escaped(line, col)
  local count = 0
  local index = col - 1
  while index >= 1 and line:sub(index, index) == "\\" do
    count = count + 1
    index = index - 1
  end
  return count % 2 == 1
end

local function code_span_ranges(line)
  local ranges = {}
  local col = 1

  while col <= #line do
    local start_col = line:find("`", col, true)
    if start_col == nil then
      break
    end
    local tick_count = 1
    while line:sub(start_col + tick_count, start_col + tick_count) == "`" do
      tick_count = tick_count + 1
    end

    local end_col = nil
    local search_col = start_col + tick_count
    while search_col <= #line do
      local candidate = line:find("`", search_col, true)
      if candidate == nil then
        break
      end
      local closing_count = 1
      while line:sub(candidate + closing_count, candidate + closing_count) == "`" do
        closing_count = closing_count + 1
      end
      if closing_count == tick_count then
        end_col = candidate + closing_count - 1
        break
      end
      search_col = candidate + closing_count
    end

    if end_col == nil then
      break
    end
    ranges[#ranges + 1] = { start_col = start_col, end_col = end_col }
    col = end_col + 1
  end

  return ranges
end

local function in_ranges(col, ranges)
  for _, range in ipairs(ranges) do
    if col >= range.start_col and col <= range.end_col then
      return true
    end
  end
  return false
end

local function valid_inline_bounds(line, open_start, close_start, open_delim, close_delim, ranges)
  if is_escaped(line, open_start) or is_escaped(line, close_start) then
    return false
  end
  if in_ranges(open_start, ranges) or in_ranges(close_start, ranges) then
    return false
  end
  if
    open_delim == "$"
    and (
      line:sub(open_start, open_start + 1) == "$$"
      or line:sub(close_start, close_start + 1) == "$$"
    )
  then
    return false
  end

  local text = line:sub(open_start + #open_delim, close_start - 1)
  if text == "" or text:find("%$") then
    return false
  end
  if text:match("^%s") or text:match("%s$") then
    return false
  end

  return true
end

local function next_inline_delimiter(line, col)
  local dollar = line:find("$", col, true)
  local paren = line:find("\\(", col, true)

  if dollar ~= nil and (paren == nil or dollar < paren) then
    return dollar, "$", "$"
  end
  if paren ~= nil then
    return paren, "\\(", "\\)"
  end
  return nil, nil, nil
end

local function inline_item(line, row, open_start, close_start, open_delim, close_delim, in_table)
  local content_start_col = open_start - 1 + #open_delim
  local content_end_col = close_start - 1
  return {
    row = row - 1,
    start_col = open_start - 1,
    opening_end_col = content_start_col,
    content_start_col = content_start_col,
    content_end_col = content_end_col,
    closing_start_col = close_start - 1,
    end_col = close_start + #close_delim - 1,
    text = line:sub(open_start + #open_delim, close_start - 1),
    delimiter = open_delim == "$" and "$" or "\\(",
    in_table = in_table,
  }
end

local function inline_items_in_range(context, start_row, end_row)
  local items = {}
  local first = math.max(1, start_row + 1)
  local last = math.min(#context.lines, end_row + 1)

  for row = first, last do
    local line = context.lines[row]
    if not context.ignored[row] then
      local code_ranges = code_span_ranges(line)
      local col = 1
      while col <= #line do
        local start_col, open_delim, close_delim = next_inline_delimiter(line, col)
        if start_col == nil then
          break
        end
        if is_escaped(line, start_col) or in_ranges(start_col, code_ranges) then
          col = start_col + 1
        elseif open_delim == "$" and line:sub(start_col, start_col + 1) == "$$" then
          col = start_col + 2
        else
          local end_col = line:find(close_delim, start_col + #open_delim, true)
          while end_col ~= nil and is_escaped(line, end_col) do
            end_col = line:find(close_delim, end_col + 1, true)
          end
          if end_col ~= nil and end_col > start_col + 1 then
            if
              valid_inline_bounds(line, start_col, end_col, open_delim, close_delim, code_ranges)
            then
              items[#items + 1] = inline_item(
                line,
                row,
                start_col,
                end_col,
                open_delim,
                close_delim,
                context.table_rows[row] == true
              )
            end
            col = end_col + #close_delim
          else
            break
          end
        end
      end
    end
  end

  return items
end

---@param bufnr integer
---@param start_row integer
---@param end_row integer
---@return table[]
function M.inline_range(bufnr, start_row, end_row)
  if end_row < start_row then
    return {}
  end

  return inline_items_in_range(scan_context(bufnr, end_row), start_row, end_row)
end

---@param bufnr integer
---@param ranges { start_row: integer, end_row: integer }[]
---@return table[]
function M.inline_ranges(bufnr, ranges)
  if #ranges == 0 then
    return {}
  end

  local max_end_row = 0
  for _, range in ipairs(ranges) do
    max_end_row = math.max(max_end_row, range.end_row)
  end
  local context = scan_context(bufnr, max_end_row)
  local items = {}
  local seen = {}
  for _, range in ipairs(ranges) do
    for _, item in ipairs(inline_items_in_range(context, range.start_row, range.end_row)) do
      local key = table.concat({ item.row, item.start_col, item.end_col }, ":")
      if not seen[key] then
        seen[key] = true
        items[#items + 1] = item
      end
    end
  end

  return items
end

---@param bufnr integer
---@return table[]
function M.inline(bufnr)
  return M.inline_range(bufnr, 0, vim.api.nvim_buf_line_count(bufnr) - 1)
end

---@param bufnr integer
---@return table[]
function M.scan(bufnr)
  return M.scan_range(bufnr, 0, vim.api.nvim_buf_line_count(bufnr) - 1)
end

---@param bufnr integer
---@param ranges { start_row: integer, end_row: integer }[]
---@return table[]
function M.scan_ranges(bufnr, ranges)
  if #ranges == 0 then
    return {}
  end

  local context = scan_context(bufnr)
  local groups = {}
  for _, range in ipairs(ranges) do
    local start_row = math.max(0, range.start_row or 0)
    local end_row = math.min(#context.lines - 1, range.end_row or -1)
    if end_row >= start_row then
      groups[#groups + 1] = merge_unique_equations(
        treesitter_equations(bufnr, context, start_row, end_row),
        dollar_equations(context, start_row, end_row),
        bracket_equations(context, start_row, end_row)
      )
    end
  end

  return sort_equations(merge_unique_equations(unpack(groups)))
end

---@param bufnr integer
---@param start_row integer
---@param end_row integer
---@return table[]
function M.scan_range(bufnr, start_row, end_row)
  if end_row < start_row then
    return {}
  end

  local context = scan_context(bufnr)
  local equations = merge_unique_equations(
    treesitter_equations(bufnr, context, start_row, end_row),
    dollar_equations(context, start_row, end_row),
    bracket_equations(context, start_row, end_row)
  )
  return sort_equations(equations)
end

---@param equations table[]
---@param bufnr integer
---@param start_row integer
---@param old_end_row integer
---@param new_end_row integer
---@return table[]
function M.update(equations, bufnr, start_row, old_end_row, new_end_row)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local line_delta = new_end_row - old_end_row
  local rescan_start = math.max(0, start_row - 50)
  local rescan_end = math.max(old_end_row, new_end_row) + 50

  for _, equation in ipairs(equations) do
    if equation.end_row >= rescan_start - 1 and equation.start_row <= rescan_end + 1 then
      rescan_start = math.min(rescan_start, math.max(0, equation.start_row - 1))
      rescan_end = math.max(rescan_end, equation.end_row + 1)
    end
  end

  local next_equations = {}
  for _, equation in ipairs(equations) do
    if equation.end_row < rescan_start or equation.start_row > rescan_end then
      local next_equation = equation
      if equation.start_row > old_end_row and line_delta ~= 0 then
        next_equation = vim.tbl_extend("force", equation, {
          start_row = equation.start_row + line_delta,
          end_row = equation.end_row + line_delta,
        })
        next_equation.key =
          equation_key(next_equation.start_row, next_equation.end_row, next_equation.text)
      end
      if next_equation.start_row >= 0 and next_equation.end_row < line_count then
        next_equations[#next_equations + 1] = next_equation
      end
    end
  end

  local scan_end = math.min(line_count - 1, rescan_end)
  vim.list_extend(next_equations, M.scan_range(bufnr, rescan_start, scan_end))
  return sort_equations(merge_unique_equations(next_equations))
end

return M
