local Config = require("render_latex.config")
local Compat = require("render_latex.compat")
local Detect = require("render_latex.detect")
local Unicode = require("render_latex.unicode")
local Util = require("render_latex.util")

local M = {}

local function set_inline_conceal(bufnr, ns, state, row, start_col, end_col, replacement)
  state.inline_marks[#state.inline_marks + 1] =
    vim.api.nvim_buf_set_extmark(bufnr, ns, row, start_col, {
      end_row = row,
      end_col = end_col,
      conceal = replacement,
      priority = 232,
    })
end

local function set_inline_symbol_marks(bufnr, ns, state, item, replacements)
  if not Config.render.inline_symbols then
    return
  end

  -- A conceal mark shows at most one character, so each output character conceals one source
  -- character and the last one also conceals the rest of the token.
  for _, range in ipairs(replacements) do
    local source = item.text:sub(range.start_col, range.end_col)
    local starts = Unicode.char_starts(source)
    local graphemes = Unicode.graphemes(range.replacement)
    local base = item.content_start_col + range.start_col - 2
    if #graphemes == 0 then
      set_inline_conceal(bufnr, ns, state, item.row, base + 1, base + #source + 1, "")
    end
    for index, grapheme in ipairs(graphemes) do
      local next_start = index < #graphemes and starts[index + 1] or #source + 1
      set_inline_conceal(
        bufnr,
        ns,
        state,
        item.row,
        base + starts[index],
        base + next_start,
        grapheme
      )
    end
  end
end

local function rendered_inline_width(item, replacements)
  local width = 0
  local index = 1
  for _, range in ipairs(replacements) do
    width = width + vim.fn.strdisplaywidth(item.text:sub(index, range.start_col - 1))
    width = width + vim.fn.strdisplaywidth(range.replacement)
    index = range.end_col + 1
  end
  width = width + vim.fn.strdisplaywidth(item.text:sub(index))
  return width
end

local function inline_delimiters(item)
  if item.delimiter == "$" then
    return "$", "$"
  end
  return "\\(", "\\)"
end

local function set_inline_table_padding(bufnr, ns, state, item, replacements)
  if not item.in_table then
    return
  end

  local opening, closing = inline_delimiters(item)
  local raw_width = vim.fn.strdisplaywidth(opening .. item.text .. closing)
  local rendered_width = rendered_inline_width(item, replacements)
  local padding = raw_width - rendered_width
  if padding <= 0 then
    return
  end

  state.inline_marks[#state.inline_marks + 1] =
    vim.api.nvim_buf_set_extmark(bufnr, ns, item.row, item.end_col, {
      virt_text = { { (" "):rep(padding), "@markup.math" } },
      virt_text_pos = "inline",
      priority = 229,
    })
end

---@param bufnr integer
---@param ns integer
---@param state render_latex.BufferState
---@param key string
function M.clear_placeholder(bufnr, ns, state, key)
  local mark_id = state.placeholders[key]
  if mark_id ~= nil then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
    state.placeholders[key] = nil
  end
end

---@param bufnr integer
---@param ns integer
---@param state render_latex.BufferState
---@param equation table
function M.set_placeholder(bufnr, ns, state, equation)
  if not Config.render.placeholder then
    return
  end

  M.clear_placeholder(bufnr, ns, state, equation.key)
  state.placeholders[equation.key] =
    vim.api.nvim_buf_set_extmark(bufnr, ns, equation.start_row, 0, {
      virt_text = { { "Rendering...", "Comment" } },
      virt_text_pos = "eol",
      priority = 260,
    })
end

---@param bufnr integer
---@param ns integer
---@param state render_latex.BufferState
---@param ranges? { start_row: integer, end_row: integer }[]
function M.render_inline_fallback(bufnr, ns, state, ranges)
  for _, mark_id in ipairs(state.inline_marks) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
  end
  state.inline_marks = {}

  if Config.render.inline == false then
    return
  end

  local items = {}
  if ranges == nil then
    items = Detect.inline(bufnr)
  else
    items = Detect.inline_ranges(bufnr, ranges)
  end
  local active = {}

  for _, winid in ipairs(Util.current_tab_wins_for_buf(bufnr)) do
    local cursor = vim.api.nvim_win_get_cursor(winid)
    local cursor_row = cursor[1] - 1
    local cursor_col = cursor[2]
    for index, item in ipairs(items) do
      if cursor_row == item.row and cursor_col >= item.start_col and cursor_col < item.end_col then
        active[index] = true
      end
    end
  end

  for index, item in ipairs(items) do
    local reveal = active[index]
    local mode = Config.render.inline

    if mode == "conceal" and not reveal then
      state.inline_marks[#state.inline_marks + 1] =
        vim.api.nvim_buf_set_extmark(bufnr, ns, item.row, item.start_col, {
          end_row = item.row,
          end_col = item.opening_end_col,
          conceal = "",
          priority = 230,
        })
      state.inline_marks[#state.inline_marks + 1] =
        vim.api.nvim_buf_set_extmark(bufnr, ns, item.row, item.closing_start_col, {
          end_row = item.row,
          end_col = item.end_col,
          conceal = "",
          priority = 230,
        })
    end

    local start_col = item.start_col
    local end_col = item.end_col
    if mode == "content" or (mode == "conceal" and not reveal) then
      start_col = item.content_start_col
      end_col = item.content_end_col
    end

    state.inline_marks[#state.inline_marks + 1] =
      vim.api.nvim_buf_set_extmark(bufnr, ns, item.row, start_col, {
        end_row = item.row,
        end_col = end_col,
        hl_group = "@markup.math",
        priority = 231,
      })

    if not reveal then
      local replacements = Config.render.inline_symbols and Unicode.replacements(item.text) or {}
      set_inline_symbol_marks(bufnr, ns, state, item, replacements)
      if mode == "conceal" then
        set_inline_table_padding(bufnr, ns, state, item, replacements)
      end
    end
  end
end

---@param bufnr integer
---@param ns integer
---@param state render_latex.BufferState
function M.clear_marks(bufnr, ns, state)
  for _, mark_id in pairs(state.marks) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
  end
  state.marks = {}

  for _, mark_id in ipairs(state.inline_marks) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
  end
  state.inline_marks = {}

  for _, mark_id in pairs(state.labels) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
  end
  state.labels = {}

  for _, mark_id in pairs(state.placeholders) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
  end
  state.placeholders = {}
end

---@param bufnr integer
---@param ns integer
---@param state render_latex.BufferState
---@param key string
function M.clear_label(bufnr, ns, state, key)
  local mark_id = state.labels[key]
  if mark_id ~= nil then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
    state.labels[key] = nil
  end
  state.label_layouts[key] = nil
end

---@param bufnr integer
---@param ns integer
---@param state render_latex.BufferState
---@param equation table
---@param index integer
function M.set_equation_label(bufnr, ns, state, equation, index)
  local style = Config.render.equation_labels
  if not style or style == false then
    M.clear_label(bufnr, ns, state, equation.key)
    return
  end

  local label = Config.render.equation_label_format:format(index)
  local layout = table.concat({ equation.start_row, style, label }, ":")
  if state.labels[equation.key] ~= nil and state.label_layouts[equation.key] == layout then
    return
  end
  M.clear_label(bufnr, ns, state, equation.key)
  local opts = { priority = 240 }

  if style == "right" or style == "both" then
    opts.virt_text = { { label, "Comment" } }
    opts.virt_text_pos = Compat.supports_eol_right_align() and "eol_right_align" or "eol"
  end
  if style == "sign" or style == "both" then
    opts.sign_text = "="
    opts.sign_hl_group = "Comment"
  end

  state.labels[equation.key] = vim.api.nvim_buf_set_extmark(bufnr, ns, equation.start_row, 0, opts)
  state.label_layouts[equation.key] = layout
end

return M
