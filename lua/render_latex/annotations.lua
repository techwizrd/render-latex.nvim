local Config = require("render_latex.config")
local Detect = require("render_latex.detect")

local M = {}

local inline_symbols = {
  alpha = "α",
  beta = "β",
  gamma = "γ",
  delta = "δ",
  epsilon = "ϵ",
  theta = "θ",
  lambda = "λ",
  mu = "μ",
  nu = "ν",
  xi = "ξ",
  pi = "π",
  rho = "ρ",
  sigma = "σ",
  tau = "τ",
  varphi = "φ",
  phi = "ϕ",
  psi = "ψ",
  omega = "ω",
  Gamma = "Γ",
  Delta = "Δ",
  Theta = "Θ",
  Lambda = "Λ",
  Pi = "Π",
  Sigma = "Σ",
  Phi = "Φ",
  Psi = "Ψ",
  Omega = "Ω",
  div = "÷",
  times = "×",
  cdot = "·",
  pm = "±",
  mp = "∓",
  oplus = "⊕",
  otimes = "⊗",
  cap = "∩",
  cup = "∪",
  wedge = "∧",
  vee = "∨",
  setminus = "∖",
  equiv = "≡",
  ne = "≠",
  neq = "≠",
  le = "≤",
  leq = "≤",
  ge = "≥",
  geq = "≥",
  approx = "≈",
  sim = "∼",
  simeq = "≃",
  cong = "≅",
  propto = "∝",
  subset = "⊂",
  subseteq = "⊆",
  supset = "⊃",
  supseteq = "⊇",
  nsubseteq = "⊈",
  nsupseteq = "⊉",
  ["in"] = "∈",
  notin = "∉",
  ni = "∋",
  emptyset = "∅",
  varnothing = "∅",
  forall = "∀",
  exists = "∃",
  nexists = "∄",
  neg = "¬",
  land = "∧",
  lor = "∨",
  implies = "⇒",
  iff = "⇔",
  infty = "∞",
  to = "→",
  rightarrow = "→",
  leftarrow = "←",
  leftrightarrow = "↔",
  Rightarrow = "⇒",
  Leftarrow = "⇐",
  Leftrightarrow = "⇔",
  mapsto = "↦",
  longrightarrow = "⟶",
  longleftarrow = "⟵",
  longleftrightarrow = "⟷",
  sum = "∑",
  prod = "∏",
  int = "∫",
  oint = "∮",
  partial = "∂",
  nabla = "∇",
  angle = "∠",
  degree = "°",
  prime = "′",
  perp = "⊥",
  parallel = "∥",
  aleph = "ℵ",
  hbar = "ℏ",
  ell = "ℓ",
  Re = "ℜ",
  Im = "ℑ",
}

local superscripts = {
  ["0"] = "⁰",
  ["1"] = "¹",
  ["2"] = "²",
  ["3"] = "³",
  ["4"] = "⁴",
  ["5"] = "⁵",
  ["6"] = "⁶",
  ["7"] = "⁷",
  ["8"] = "⁸",
  ["9"] = "⁹",
  ["+"] = "⁺",
  ["-"] = "⁻",
  ["="] = "⁼",
  ["("] = "⁽",
  [")"] = "⁾",
  n = "ⁿ",
  i = "ⁱ",
}

local subscripts = {
  ["0"] = "₀",
  ["1"] = "₁",
  ["2"] = "₂",
  ["3"] = "₃",
  ["4"] = "₄",
  ["5"] = "₅",
  ["6"] = "₆",
  ["7"] = "₇",
  ["8"] = "₈",
  ["9"] = "₉",
  ["+"] = "₊",
  ["-"] = "₋",
  ["="] = "₌",
  ["("] = "₍",
  [")"] = "₎",
  a = "ₐ",
  e = "ₑ",
  h = "ₕ",
  i = "ᵢ",
  j = "ⱼ",
  k = "ₖ",
  l = "ₗ",
  m = "ₘ",
  n = "ₙ",
  o = "ₒ",
  p = "ₚ",
  r = "ᵣ",
  s = "ₛ",
  t = "ₜ",
  u = "ᵤ",
  v = "ᵥ",
  x = "ₓ",
}

local function set_inline_conceal(bufnr, ns, state, row, start_col, end_col, replacement)
  state.inline_marks[#state.inline_marks + 1] =
    vim.api.nvim_buf_set_extmark(bufnr, ns, row, start_col, {
      end_row = row,
      end_col = end_col,
      conceal = replacement,
      priority = 232,
    })
end

local function inline_symbol_replacements(item)
  local replacements = {}
  local text = item.text
  local index = 1
  while index <= #text do
    local command_start, command_end, name = text:find("\\([A-Za-z]+)", index)
    local script_start, script_end, marker, value = text:find("([%^_])([%w%+%-%=%(%)])", index)
    local braced_start, braced_end, braced_marker, braced_value =
      text:find("([%^_])%{([%w%+%-%=%(%)])%}", index)

    if braced_start ~= nil and (script_start == nil or braced_start < script_start) then
      script_start = braced_start
      script_end = braced_end
      marker = braced_marker
      value = braced_value
    end

    if command_start == nil and script_start == nil then
      break
    end

    if script_start ~= nil and (command_start == nil or script_start < command_start) then
      local replacement = marker == "^" and superscripts[value] or subscripts[value]
      if replacement ~= nil then
        replacements[#replacements + 1] = {
          start_col = script_start,
          end_col = script_end,
          replacement = replacement,
        }
      end
      index = script_end + 1
    else
      local replacement = inline_symbols[name]
      if replacement ~= nil then
        replacements[#replacements + 1] = {
          start_col = command_start,
          end_col = command_end,
          replacement = replacement,
        }
      end
      index = command_end + 1
    end
  end
  return replacements
end

local function set_inline_symbol_marks(bufnr, ns, state, item, replacements)
  if not Config.render.inline_symbols then
    return
  end

  for _, range in ipairs(replacements) do
    set_inline_conceal(
      bufnr,
      ns,
      state,
      item.row,
      item.content_start_col + range.start_col - 1,
      item.content_start_col + range.end_col,
      range.replacement
    )
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

  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(winid) then
      local cursor = vim.api.nvim_win_get_cursor(winid)
      local cursor_row = cursor[1] - 1
      local cursor_col = cursor[2]
      for index, item in ipairs(items) do
        if
          cursor_row == item.row
          and cursor_col >= item.start_col
          and cursor_col < item.end_col
        then
          active[index] = true
        end
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
      local replacements = Config.render.inline_symbols and inline_symbol_replacements(item) or {}
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
    return
  end

  M.clear_label(bufnr, ns, state, equation.key)
  local label = Config.render.equation_label_format:format(index)
  local layout = table.concat({ equation.start_row, style, label }, ":")
  if state.labels[equation.key] ~= nil and state.label_layouts[equation.key] == layout then
    return
  end
  local opts = { priority = 240 }

  if style == "right" or style == "both" then
    opts.virt_text = { { label, "Comment" } }
    opts.virt_text_pos = "eol_right_align"
  end
  if style == "sign" or style == "both" then
    opts.sign_text = "="
    opts.sign_hl_group = "Comment"
  end

  state.labels[equation.key] = vim.api.nvim_buf_set_extmark(bufnr, ns, equation.start_row, 0, opts)
  state.label_layouts[equation.key] = layout
end

return M
