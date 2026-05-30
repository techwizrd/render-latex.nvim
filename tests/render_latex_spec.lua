---@module 'luassert'

local render_latex = require("render_latex")
local annotations = require("render_latex.annotations")
local compat = require("render_latex.compat")
local config = require("render_latex.config")
local detect = require("render_latex.detect")
local image_backend = require("render_latex.image_backend")
local integrations = require("render_latex.integrations")
local install = require("render_latex.install")
local renderer = require("render_latex.renderer")
local tmux = require("render_latex.tmux")
local ui = require("render_latex.ui")
local util = require("render_latex.util")
local viewport = require("render_latex.viewport")
local worker = require("render_latex.worker")

describe("render_latex.detect", function()
  it("falls back when markdown_inline query parsing is unavailable", function()
    local previous_detect = package.loaded["render_latex.detect"]
    local previous_parse = vim.treesitter.query.parse
    vim.treesitter.query.parse = function(lang, query)
      if lang == "markdown_inline" then
        error("missing parser")
      end
      return previous_parse(lang, query)
    end
    package.loaded["render_latex.detect"] = nil

    local ok, fallback_detect = pcall(require, "render_latex.detect")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "$$", "x^2", "$$" })
    local equations = ok and fallback_detect.scan(buf) or {}

    package.loaded["render_latex.detect"] = previous_detect
    vim.treesitter.query.parse = previous_parse

    assert.is_true(ok)
    assert.are.equal(1, #equations)
    assert.are.equal("$$", equations[1].delimiter)
  end)

  it("finds $$ display math blocks", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "before",
      "$$",
      "x^2 + y^2",
      "$$",
      "after",
    })

    local equations = detect.scan(buf)
    assert.are.equal(1, #equations)
    assert.are.equal(1, equations[1].start_row)
    assert.are.equal(3, equations[1].end_row)
    assert.are.equal("display", equations[1].kind)
    assert.are.equal("$$", equations[1].delimiter)
  end)

  it("finds single-line $$ display math blocks", function()
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "$$ \\frac{1}{2} $$",
    })

    local equations = detect.scan(buf)
    assert.are.equal(1, #equations)
    assert.are.equal("\\frac{1}{2}", equations[1].text)
  end)

  it("drops display math deleted from the final line", function()
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "before",
      "$$x$$",
    })
    local equations = detect.scan(buf)

    vim.api.nvim_buf_set_lines(buf, 1, 2, false, {})
    equations = detect.update(equations, buf, 1, 1, 0)

    assert.are.equal(0, #equations)
  end)

  it("shifts cached equations after deleted lines", function()
    local lines = {}
    for index = 1, 60 do
      lines[index] = "line " .. index
    end
    lines[#lines + 1] = "$$x$$"

    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local equations = detect.scan(buf)

    vim.api.nvim_buf_set_lines(buf, 0, 1, false, {})
    equations = detect.update(equations, buf, 0, 0, -1)

    assert.are.equal(1, #equations)
    assert.are.equal(59, equations[1].start_row)
    assert.are.equal(59, equations[1].end_row)
  end)

  it("finds bracket display math blocks", function()
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "\\[",
      "\\frac{1}{2}",
      "\\]",
    })

    local equations = detect.scan(buf)
    assert.are.equal(1, #equations)
    assert.are.equal(0, equations[1].start_row)
    assert.are.equal(2, equations[1].end_row)
    assert.are.equal("\\frac{1}{2}", equations[1].text)
    assert.are.equal("display", equations[1].kind)
    assert.are.equal("\\[", equations[1].delimiter)
  end)

  it("finds single-line bracket display math blocks", function()
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "\\[ x + y \\]",
    })

    local equations = detect.scan(buf)
    assert.are.equal(1, #equations)
    assert.are.equal("x + y", equations[1].text)
    assert.are.equal("\\[", equations[1].delimiter)
  end)

  it("ignores display math inside fenced code blocks", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "```",
      "$$",
      "x^2",
      "$$",
      "\\[ y \\]",
      "```",
      "$$ z $$",
    })

    local equations = detect.scan(buf)
    assert.are.equal(1, #equations)
    assert.are.equal("z", equations[1].text)
  end)

  it("keeps shorter matching markers inside longer fenced code blocks", function()
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "````",
      "```",
      "$$ hidden $$",
      "```",
      "````",
      "$$ visible $$",
    })

    local equations = detect.scan(buf)

    assert.are.equal(1, #equations)
    assert.are.equal("visible", equations[1].text)
  end)

  it("ignores display and inline math inside YAML frontmatter", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "---",
      "title: $not_inline$",
      "equation: $$ not_display $$",
      "bracket: \\[ not_display \\]",
      "---",
      "real $inline$",
      "$$ real $$",
    })

    local equations = detect.scan(buf)
    local inline = detect.inline(buf)

    assert.are.equal(1, #equations)
    assert.are.equal("real", equations[1].text)
    assert.are.equal(1, #inline)
    assert.are.equal("inline", inline[1].text)
  end)

  it("finds display math inside blockquotes and Obsidian callouts", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "> [!NOTE]",
      "> $$",
      "> x^2 + y^2",
      "> $$",
      "> \\[",
      "> z^2",
      "> \\]",
    })

    local equations = detect.scan(buf)

    assert.are.equal(2, #equations)
    assert.are.equal("x^2 + y^2", equations[1].text)
    assert.are.equal("z^2", equations[2].text)
    assert.is_true(equations[1].quoted)
    assert.is_true(equations[2].quoted)
  end)

  it("marks regular display math as unquoted", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "$$",
      "x^2",
      "$$",
    })

    local equations = detect.scan(buf)

    assert.are.equal(1, #equations)
    assert.is_false(equations[1].quoted)
  end)

  it("does not promote inline math in tables or lists to display math", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "| value | math |",
      "| --- | --- |",
      "| one | $x + y$ |",
      "- list item with $a^2$",
    })

    local equations = detect.scan(buf)
    local inline = detect.inline(buf)

    assert.are.equal(0, #equations)
    assert.are.equal(2, #inline)
    assert.is_true(inline[1].in_table)
    assert.is_false(inline[2].in_table)
  end)

  it("ignores math inside Obsidian comments", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "%%",
      "hidden $inline$",
      "$$ hidden $$",
      "%%",
      "visible $inline$",
      "$$ visible $$",
    })

    local equations = detect.scan(buf)
    local inline = detect.inline(buf)

    assert.are.equal(1, #equations)
    assert.are.equal("visible", equations[1].text)
    assert.are.equal(1, #inline)
    assert.are.equal("inline", inline[1].text)
  end)

  it("ignores math inside indented code blocks", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "    $hidden$",
      "    $$ hidden $$",
      "visible $inline$",
      "$$ visible $$",
    })

    local equations = detect.scan(buf)
    local inline = detect.inline(buf)

    assert.are.equal(1, #equations)
    assert.are.equal("visible", equations[1].text)
    assert.are.equal(1, #inline)
    assert.are.equal("inline", inline[1].text)
  end)

  it("finds display math inside nested blockquotes", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "> > $$",
      "> > nested",
      "> > $$",
    })

    local equations = detect.scan(buf)

    assert.are.equal(1, #equations)
    assert.are.equal("nested", equations[1].text)
  end)

  it("finds punctuation-adjacent inline math", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "Use ($x$), then $y$.",
    })

    local inline = detect.inline(buf)

    assert.are.equal(2, #inline)
    assert.are.equal("x", inline[1].text)
    assert.are.equal("y", inline[2].text)
  end)

  it("ignores unclosed display math blocks", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "before",
      "$$",
      "x^2",
      "after",
    })

    assert.are.equal(0, #detect.scan(buf))
  end)

  it("does not treat inline math as display math", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "before $x + y$ after",
    })

    local equations = detect.scan(buf)
    local inline = detect.inline(buf)

    assert.are.equal(0, #equations)
    assert.are.equal(1, #inline)
    assert.are.equal("x + y", inline[1].text)
    assert.are.equal(8, inline[1].content_start_col)
    assert.are.equal(13, inline[1].content_end_col)
  end)

  it("finds multiple inline math spans on one line", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "$a$ and $b$",
    })

    local inline = detect.inline(buf)
    assert.are.equal(2, #inline)
    assert.are.equal("a", inline[1].text)
    assert.are.equal("b", inline[2].text)
  end)

  it("finds parenthesized inline math spans", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "before \\(x + y\\) after",
    })

    local inline = detect.inline(buf)
    assert.are.equal(1, #inline)
    assert.are.equal("x + y", inline[1].text)
    assert.are.equal("\\(", inline[1].delimiter)
    assert.are.equal(7, inline[1].start_col)
    assert.are.equal(9, inline[1].content_start_col)
    assert.are.equal(14, inline[1].content_end_col)
    assert.are.equal(16, inline[1].end_col)
  end)

  it("ignores escaped dollars and inline code", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "escaped \\$x$ and code `$y$` but real $z$",
    })

    local inline = detect.inline(buf)
    assert.are.equal(1, #inline)
    assert.are.equal("z", inline[1].text)
  end)

  it("ignores escaped parenthesized inline math", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "escaped \\\\(x\\) but real \\(y\\)",
    })

    local inline = detect.inline(buf)
    assert.are.equal(1, #inline)
    assert.are.equal("y", inline[1].text)
  end)

  it("ignores inline math in multi-backtick code spans", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "code ``$x$ and \\(y\\)`` but real $z$",
    })

    local inline = detect.inline(buf)
    assert.are.equal(1, #inline)
    assert.are.equal("z", inline[1].text)
  end)

  it("ignores inline math in fenced code blocks", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "```",
      "$x$ and \\(y\\)",
      "```",
      "real $z$",
    })

    local inline = detect.inline(buf)
    assert.are.equal(1, #inline)
    assert.are.equal("z", inline[1].text)
  end)

  it("ignores currency-shaped dollar pairs", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "price is $5 and another is $6",
    })

    assert.are.equal(0, #detect.inline(buf))
  end)

  it("does not treat display dollars as inline math", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "$$x$$",
    })

    assert.are.equal(0, #detect.inline(buf))
    assert.are.equal(1, #detect.scan(buf))
  end)

  it("scans multiple inline ranges with one full-buffer read", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = {}
    for index = 1, 200 do
      lines[index] = index % 50 == 0 and ("line $x_" .. index .. "$") or "plain text"
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local original_get_lines = vim.api.nvim_buf_get_lines
    local calls = 0
    vim.api.nvim_buf_get_lines = function(...)
      calls = calls + 1
      return original_get_lines(...)
    end

    local ok, items = pcall(detect.inline_ranges, buf, {
      { start_row = 0, end_row = 60 },
      { start_row = 100, end_row = 160 },
    })
    vim.api.nvim_buf_get_lines = original_get_lines

    assert.is_true(ok)
    assert.are.equal(2, #items)
    assert.are.equal(1, calls)
  end)
end)

describe("render_latex.annotations", function()
  it("conceals inline math delimiters by default", function()
    config.setup({ render_modes = { vim.api.nvim_get_mode().mode } })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before $xy$ after" })
    local ns = vim.api.nvim_create_namespace("render-latex-test-conceal")
    local state = { inline_marks = {} }

    annotations.render_inline_fallback(buf, ns, state)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })

    assert.are.equal(3, #marks)
    assert.are.equal("", marks[1][4].conceal)
    assert.are.equal("@markup.math", marks[2][4].hl_group)
    assert.are.equal("", marks[3][4].conceal)
  end)

  it("conceals common inline math symbols", function()
    config.setup({ render_modes = { vim.api.nvim_get_mode().mode } })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { [[Euler $e^{i\pi} + 1 \leq 0, x \in A$]] })
    local ns = vim.api.nvim_create_namespace("render-latex-test-symbols")
    local state = { inline_marks = {} }

    annotations.render_inline_fallback(buf, ns, state)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local conceals = {}
    for _, mark in ipairs(marks) do
      if mark[4].conceal ~= nil then
        conceals[mark[4].conceal] = true
      end
    end

    assert.is_true(conceals[""])
    assert.is_true(conceals["π"])
    assert.is_true(conceals["≤"])
    assert.is_true(conceals["∈"])
  end)

  it("pads concealed inline math inside markdown tables", function()
    config.setup({ render_modes = { vim.api.nvim_get_mode().mode } })
    local raw_row = [[| row | $x \in A$ |]]
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "| Item | Math |",
      "| --- | --- |",
      raw_row,
    })
    local ns = vim.api.nvim_create_namespace("render-latex-test-table-padding")
    local state = { inline_marks = {} }

    annotations.render_inline_fallback(buf, ns, state)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local padding = nil
    local conceals = {}
    for _, mark in ipairs(marks) do
      if mark[4].virt_text_pos == "inline" then
        padding = mark
      end
      if mark[4].conceal ~= nil then
        conceals[mark[4].conceal] = true
      end
    end

    assert.is_truthy(padding)
    assert.are.equal(2, padding[2])
    assert.are.equal(4, vim.fn.strdisplaywidth(padding[4].virt_text[1][1]))
    assert.are.equal(
      vim.fn.strdisplaywidth(raw_row),
      vim.fn.strdisplaywidth("| row | x ∈ A" .. padding[4].virt_text[1][1] .. " |")
    )
    assert.is_true(conceals[""])
    assert.is_true(conceals["∈"])
  end)

  it("respects disabled inline symbols when padding table math", function()
    config.setup({ render = { inline_symbols = false } })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "| Item | Math |",
      "| --- | --- |",
      [[| row | $x \in A$ |]],
    })
    local ns = vim.api.nvim_create_namespace("render-latex-test-table-padding-no-symbols")
    local state = { inline_marks = {} }

    annotations.render_inline_fallback(buf, ns, state)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local padding = nil
    local symbol_conceals = 0
    for _, mark in ipairs(marks) do
      if mark[4].virt_text_pos == "inline" then
        padding = mark
      end
      if mark[4].conceal ~= nil and mark[4].conceal ~= "" then
        symbol_conceals = symbol_conceals + 1
      end
    end

    assert.is_truthy(padding)
    assert.are.equal(2, vim.fn.strdisplaywidth(padding[4].virt_text[1][1]))
    assert.are.equal(0, symbol_conceals)
  end)

  it("conceals broader inline math symbols", function()
    config.setup()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      [[sets $x \notin A \subseteq B \Rightarrow \exists y \in B \land y \neq x$]],
    })
    local ns = vim.api.nvim_create_namespace("render-latex-test-broad-symbols")
    local state = { inline_marks = {} }

    annotations.render_inline_fallback(buf, ns, state)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local conceals = {}
    for _, mark in ipairs(marks) do
      if mark[4].conceal ~= nil then
        conceals[mark[4].conceal] = true
      end
    end

    assert.is_true(conceals["∉"])
    assert.is_true(conceals["⊆"])
    assert.is_true(conceals["⇒"])
    assert.is_true(conceals["∃"])
    assert.is_true(conceals["∈"])
    assert.is_true(conceals["∧"])
    assert.is_true(conceals["≠"])
  end)

  it("conceals full inline symbol command ranges", function()
    config.setup()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { [[Euler $e^{i\pi} + 1 \leq 0$]] })
    local ns = vim.api.nvim_create_namespace("render-latex-test-symbol-ranges")
    local state = { inline_marks = {} }

    annotations.render_inline_fallback(buf, ns, state)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local pi_mark = nil
    local leq_mark = nil
    for _, mark in ipairs(marks) do
      if mark[4].conceal == "π" then
        pi_mark = mark
      elseif mark[4].conceal == "≤" then
        leq_mark = mark
      end
    end

    assert.is_truthy(pi_mark)
    assert.are.equal(11, pi_mark[3])
    assert.are.equal(14, pi_mark[4].end_col)
    assert.are.equal(
      [[\pi]],
      vim.api.nvim_buf_get_text(buf, 0, pi_mark[3], 0, pi_mark[4].end_col, {})[1]
    )

    assert.is_truthy(leq_mark)
    assert.are.equal(
      [[\leq]],
      vim.api.nvim_buf_get_text(buf, 0, leq_mark[3], 0, leq_mark[4].end_col, {})[1]
    )
  end)

  it("conceals simple inline math superscripts and subscripts", function()
    config.setup()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { [[formula $x^2_i + y^{3}$]] })
    local ns = vim.api.nvim_create_namespace("render-latex-test-scripts")
    local state = { inline_marks = {} }

    annotations.render_inline_fallback(buf, ns, state)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local conceals = {}
    for _, mark in ipairs(marks) do
      if mark[4].conceal ~= nil then
        conceals[mark[4].conceal] = true
      end
    end

    assert.is_true(conceals["²"])
    assert.is_true(conceals["ᵢ"])
    assert.is_true(conceals["³"])
  end)

  it("can disable inline math symbol conceals", function()
    config.setup({ render = { inline_symbols = false } })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { [[Euler $e^{i\pi}$]] })
    local ns = vim.api.nvim_create_namespace("render-latex-test-symbols-disabled")
    local state = { inline_marks = {} }

    annotations.render_inline_fallback(buf, ns, state)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local symbol_conceals = 0
    for _, mark in ipairs(marks) do
      if mark[4].conceal ~= nil and mark[4].conceal ~= "" then
        symbol_conceals = symbol_conceals + 1
      end
    end

    assert.are.equal(0, symbol_conceals)
  end)

  it("can highlight inline math without concealing delimiters", function()
    config.setup({ render = { inline = "highlight" } })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before $x$ after" })
    local ns = vim.api.nvim_create_namespace("render-latex-test-highlight")
    local state = { inline_marks = {} }

    annotations.render_inline_fallback(buf, ns, state)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })

    assert.are.equal(1, #marks)
    assert.are.equal("@markup.math", marks[1][4].hl_group)
    assert.are.equal(7, marks[1][3])
    assert.are.equal(10, marks[1][4].end_col)
  end)

  it("can highlight only inline math content", function()
    config.setup({ render = { inline = "content" } })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before $x$ after" })
    local ns = vim.api.nvim_create_namespace("render-latex-test-content")
    local state = { inline_marks = {} }

    annotations.render_inline_fallback(buf, ns, state)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })

    assert.are.equal(1, #marks)
    assert.are.equal("@markup.math", marks[1][4].hl_group)
    assert.are.equal(8, marks[1][3])
    assert.are.equal(9, marks[1][4].end_col)
  end)

  it("conceals parenthesized inline math delimiters", function()
    config.setup()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before \\(x\\) after" })
    local ns = vim.api.nvim_create_namespace("render-latex-test-paren-conceal")
    local state = { inline_marks = {} }

    annotations.render_inline_fallback(buf, ns, state)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })

    assert.are.equal(3, #marks)
    assert.are.equal(7, marks[1][3])
    assert.are.equal(9, marks[1][4].end_col)
    assert.are.equal("@markup.math", marks[2][4].hl_group)
    assert.are.equal(9, marks[2][3])
    assert.are.equal(10, marks[2][4].end_col)
    assert.are.equal(10, marks[3][3])
    assert.are.equal(12, marks[3][4].end_col)
  end)

  it("reveals inline math delimiters under the cursor", function()
    config.setup()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { [[before $\pi$ after]] })
    vim.api.nvim_win_set_cursor(0, { 1, 8 })
    local ns = vim.api.nvim_create_namespace("render-latex-test-reveal")
    local state = { inline_marks = {} }

    annotations.render_inline_fallback(buf, ns, state)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })

    assert.are.equal(1, #marks)
    assert.are.equal("@markup.math", marks[1][4].hl_group)
    assert.are.equal(nil, marks[1][4].conceal)
    assert.are.equal(7, marks[1][3])
    assert.are.equal(12, marks[1][4].end_col)
  end)

  it("can disable inline math fallback marks", function()
    config.setup({ render = { inline = false } })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before $x$ after" })
    local ns = vim.api.nvim_create_namespace("render-latex-test-disabled")
    local state = { inline_marks = {} }

    annotations.render_inline_fallback(buf, ns, state)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })

    assert.are.equal(0, #marks)
  end)
end)

describe("render_latex.config", function()
  it("rejects invalid nested enum values", function()
    assert.has.errors(function()
      config.setup({ render = { inline = "image" } })
    end)
    assert.has.errors(function()
      config.setup({ image = { backend = "sixel" } })
    end)
    config.setup()
  end)

  it("rejects invalid nested numeric values", function()
    assert.has.errors(function()
      config.setup({ image = { cell_width_px = 0 } })
    end)
    assert.has.errors(function()
      config.setup({ render = { scale = -1 } })
    end)
    config.setup()
  end)

  it("rejects invalid nested boolean values", function()
    assert.has.errors(function()
      config.setup({ render = { hide_on_cmdline = "yes" } })
    end)
    config.setup()
  end)

  it("accepts install options", function()
    config.setup({ install = { auto = false, repository = "techwizrd/render-latex.nvim" } })

    assert.is_false(config.install.auto)
    assert.are.equal("techwizrd/render-latex.nvim", config.install.repository)
  end)
end)

describe("render_latex.install", function()
  local previous_system
  local previous_echo
  local previous_executable
  local previous_mkdir
  local previous_delete
  local previous_rename
  local previous_os_uname

  before_each(function()
    previous_system = vim.system
    previous_echo = vim.api.nvim_echo
    previous_executable = vim.fn.executable
    previous_mkdir = vim.fn.mkdir
    previous_delete = vim.fn.delete
    previous_rename = vim.uv.fs_rename
    previous_os_uname = vim.uv.os_uname
    install.reset_for_tests()
    config.setup()
  end)

  after_each(function()
    vim.system = previous_system
    vim.api.nvim_echo = previous_echo
    vim.fn.executable = previous_executable
    vim.fn.mkdir = previous_mkdir
    vim.fn.delete = previous_delete
    vim.uv.fs_rename = previous_rename
    vim.uv.os_uname = previous_os_uname
    install.reset_for_tests()
    config.setup()
  end)

  it("normalizes supported platform names", function()
    assert.are.equal("linux-x64", install._system_key_from_uname("Linux", "x86_64"))
    assert.are.equal("linux-arm64", install._system_key_from_uname("Linux", "aarch64"))
    assert.are.equal("macos-x64", install._system_key_from_uname("Darwin", "x86_64"))
    assert.are.equal("macos-arm64", install._system_key_from_uname("Darwin", "arm64"))
    assert.are.equal("windows-x64", install._system_key_from_uname("Windows_NT", "AMD64"))
    assert.are.equal("windows-arm64", install._system_key_from_uname("Windows_NT", "ARM64"))
    assert.is_nil(install._system_key_from_uname("Plan9", "x86_64"))
  end)

  it("builds release asset URLs", function()
    config.setup({ install = { repository = "techwizrd/render-latex.nvim", version = "v1.2.3" } })
    local url = install.asset_url()

    if url ~= nil then
      assert.matches(
        "https://github%.com/techwizrd/render%-latex%.nvim/releases/download/v1%.2%.3/render%-latex%-worker%-",
        url
      )
    end
  end)

  it("builds the worker asynchronously with native progress updates", function()
    local progress = {}
    local on_exit
    local ready_path, ready_operation
    local callback_path, callback_err

    vim.api.nvim_echo = function(chunks, _, opts)
      progress[#progress + 1] = { text = chunks[1][1], opts = vim.deepcopy(opts) }
      return opts.id or #progress
    end
    vim.system = function(command, opts, callback)
      assert.are.same(
        { "cargo", "build", "--release", "--package", "render-latex-worker" },
        command
      )
      assert.are.equal(vim.fs.normalize(util.root()), vim.fs.normalize(opts.cwd))
      on_exit = callback
      return {}
    end
    install.on_worker_ready(function(path, operation)
      ready_path = path
      ready_operation = operation
    end)

    install.build_worker(true, function(path, err)
      callback_path = path
      callback_err = err
    end)

    assert.is_true(install.status().building)
    assert.are.equal("running", progress[1].opts.status)
    assert.are.equal("render-latex worker build", progress[1].opts.title)

    on_exit({ code = 0, stderr = "" })

    vim.wait(100, function()
      return callback_path ~= nil or callback_err ~= nil
    end)

    assert.are.equal(install.local_worker_path(), callback_path)
    assert.is_nil(callback_err)
    assert.are.equal(install.local_worker_path(), ready_path)
    assert.are.equal("build", ready_operation)
    assert.is_false(install.status().building)
    assert.are.equal("success", progress[#progress].opts.status)
    assert.are.equal("Built render-latex worker", progress[#progress].text)
  end)

  it("records async build failures and does not notify readiness", function()
    local progress = {}
    local on_exit
    local ready_called = false
    local callback_path, callback_err

    vim.api.nvim_echo = function(chunks, _, opts)
      progress[#progress + 1] = { text = chunks[1][1], opts = vim.deepcopy(opts) }
      return opts.id or #progress
    end
    vim.system = function(_, _, callback)
      on_exit = callback
      return {}
    end
    install.on_worker_ready(function()
      ready_called = true
    end)

    install.build_worker(true, function(path, err)
      callback_path = path
      callback_err = err
    end)
    on_exit({ code = 1, stderr = "cargo failed" })

    vim.wait(100, function()
      return callback_err ~= nil
    end)

    assert.is_nil(callback_path)
    assert.are.equal("cargo failed", callback_err)
    assert.is_false(ready_called)
    assert.is_false(install.status().building)
    assert.are.equal("cargo failed", install.status().build_error)
    assert.are.equal("error", progress[#progress].opts.status)
  end)

  it("notifies shared readiness listeners after install succeeds", function()
    local progress = {}
    local on_exit
    local callback_path, callback_err
    local ready_path, ready_operation

    vim.api.nvim_echo = function(chunks, _, opts)
      progress[#progress + 1] = { text = chunks[1][1], opts = vim.deepcopy(opts) }
      return opts.id or #progress
    end
    vim.fn.executable = function(name)
      if name == "curl" then
        return 1
      end
      return 0
    end
    vim.fn.mkdir = function() end
    vim.fn.delete = function() end
    vim.uv.fs_rename = function()
      return true
    end
    vim.system = function(command, _, callback)
      assert.are.equal("curl", command[1])
      on_exit = callback
      return {}
    end
    install.on_worker_ready(function(path, operation)
      ready_path = path
      ready_operation = operation
    end)

    install.install_worker(true, function(path, err)
      callback_path = path
      callback_err = err
    end)

    assert.is_true(install.status().installing)
    assert.are.equal("running", progress[1].opts.status)

    on_exit({ code = 0, stderr = "" })

    vim.wait(100, function()
      return callback_path ~= nil or callback_err ~= nil
    end)

    assert.are.equal(install.managed_worker_path(), callback_path)
    assert.is_nil(callback_err)
    assert.are.equal(install.managed_worker_path(), ready_path)
    assert.are.equal("install", ready_operation)
    assert.is_false(install.status().installing)
    assert.are.equal("success", progress[#progress].opts.status)
  end)

  it("falls back to unreleased for missing latest Linux ARM64 assets", function()
    local commands = {}
    local callbacks = {}
    local callback_path, callback_err

    config.setup({ install = { repository = "techwizrd/render-latex.nvim", version = "latest" } })
    vim.uv.os_uname = function()
      return { sysname = "Linux", machine = "aarch64" }
    end
    vim.fn.executable = function(name)
      return name == "curl" and 1 or 0
    end
    vim.fn.mkdir = function() end
    vim.fn.delete = function() end
    vim.uv.fs_rename = function()
      return true
    end
    vim.system = function(command, _, callback)
      commands[#commands + 1] = command
      callbacks[#callbacks + 1] = callback
      return {}
    end

    install.install_worker(false, function(path, err)
      callback_path = path
      callback_err = err
    end)

    assert.matches("/releases/latest/download/render%-latex%-worker%-linux%-arm64$", commands[1][7])
    callbacks[1]({ code = 22, stderr = "404" })

    vim.wait(100, function()
      return #commands == 2
    end)

    assert.matches(
      "/releases/download/unreleased/render%-latex%-worker%-linux%-arm64$",
      commands[2][7]
    )
    callbacks[2]({ code = 0, stderr = "" })

    vim.wait(100, function()
      return callback_path ~= nil or callback_err ~= nil
    end)

    assert.are.equal(install.managed_worker_path(), callback_path)
    assert.is_nil(callback_err)
    assert.is_false(install.status().installing)
  end)

  it("does not fall back to unreleased for pinned Linux ARM64 installs", function()
    local commands = {}
    local callbacks = {}
    local callback_path, callback_err

    config.setup({ install = { repository = "techwizrd/render-latex.nvim", version = "v1.2.3" } })
    vim.uv.os_uname = function()
      return { sysname = "Linux", machine = "aarch64" }
    end
    vim.fn.executable = function(name)
      return name == "curl" and 1 or 0
    end
    vim.fn.mkdir = function() end
    vim.fn.delete = function() end
    vim.system = function(command, _, callback)
      commands[#commands + 1] = command
      callbacks[#callbacks + 1] = callback
      return {}
    end

    install.install_worker(false, function(path, err)
      callback_path = path
      callback_err = err
    end)

    assert.matches(
      "/releases/download/v1%.2%.3/render%-latex%-worker%-linux%-arm64$",
      commands[1][7]
    )
    callbacks[1]({ code = 22, stderr = "404" })

    vim.wait(100, function()
      return callback_err ~= nil
    end)

    assert.are.equal(1, #commands)
    assert.is_nil(callback_path)
    assert.matches("failed to download render%-latex worker", callback_err)
    assert.is_false(install.status().installing)
  end)

  it("falls back to unreleased for latest Windows ARM64 installs", function()
    local commands = {}
    local callbacks = {}
    local callback_path, callback_err

    config.setup({ install = { repository = "techwizrd/render-latex.nvim", version = "latest" } })
    vim.uv.os_uname = function()
      return { sysname = "Windows_NT", machine = "ARM64" }
    end
    vim.fn.executable = function(name)
      return name == "curl" and 1 or 0
    end
    vim.fn.mkdir = function() end
    vim.fn.delete = function() end
    vim.uv.fs_rename = function()
      return true
    end
    vim.system = function(command, _, callback)
      commands[#commands + 1] = command
      callbacks[#callbacks + 1] = callback
      return {}
    end

    install.install_worker(false, function(path, err)
      callback_path = path
      callback_err = err
    end)

    assert.matches(
      "/releases/latest/download/render%-latex%-worker%-windows%-arm64%.exe$",
      commands[1][7]
    )
    callbacks[1]({ code = 22, stderr = "404" })

    vim.wait(100, function()
      return #commands == 2
    end)

    assert.matches(
      "/releases/download/unreleased/render%-latex%-worker%-windows%-arm64%.exe$",
      commands[2][7]
    )
    callbacks[2]({ code = 0, stderr = "" })

    vim.wait(100, function()
      return callback_path ~= nil or callback_err ~= nil
    end)

    assert.are.equal(install.managed_worker_path(), callback_path)
    assert.is_nil(callback_err)
    assert.is_false(install.status().installing)
  end)
end)

describe("render_latex.setup", function()
  it("defers automatic install until user setup options are applied", function()
    local previous_ensure = install.ensure_installed_async
    local auto_values = {}

    install.ensure_installed_async = function()
      auto_values[#auto_values + 1] = config.install.auto
    end

    render_latex.setup()
    render_latex.setup({ install = { auto = false } })

    vim.wait(100, function()
      return #auto_values >= 2
    end)

    install.ensure_installed_async = previous_ensure

    assert.are.same({ false, false }, auto_values)
  end)

  it("can be called repeatedly without duplicating autocmds", function()
    render_latex.setup({ install = { auto = false }, render = { inline = "highlight" } })
    local first = #vim.api.nvim_get_autocmds({ group = config.augroup })

    render_latex.setup({ install = { auto = false }, render = { inline = "conceal" } })
    local second = #vim.api.nvim_get_autocmds({ group = config.augroup })

    assert.are.equal(first, second)
    assert.are.equal("conceal", config.render.inline)
  end)

  it("requeues all visible markdown buffers on ColorScheme", function()
    local previous_list_wins = vim.api.nvim_list_wins
    local previous_win_get_config = vim.api.nvim_win_get_config
    local previous_win_get_buf = vim.api.nvim_win_get_buf
    local previous_attach = renderer.attach
    local previous_queue = renderer.queue
    local previous_suppression = renderer.suppression_status
    local previous_set_suppressed = renderer.set_suppressed
    local previous_has_popup = ui.has_popup_or_floating_windows
    local previous_getcmdtype = vim.fn.getcmdtype
    local attached = {}
    local queued = {}

    renderer.attach = function(bufnr)
      attached[#attached + 1] = bufnr
    end
    renderer.queue = function(bufnr)
      queued[#queued + 1] = bufnr
    end
    renderer.suppression_status = function()
      return { cmdline = false, floating = false }
    end
    renderer.set_suppressed = function() end
    ui.has_popup_or_floating_windows = function()
      return false
    end
    vim.fn.getcmdtype = function()
      return ""
    end

    local left = vim.api.nvim_create_buf(false, true)
    local right = vim.api.nvim_create_buf(false, true)
    vim.bo[left].filetype = "markdown"
    vim.bo[right].filetype = "markdown"
    vim.api.nvim_list_wins = function()
      return { 101, 202 }
    end
    vim.api.nvim_win_get_config = function()
      return { relative = "" }
    end
    vim.api.nvim_win_get_buf = function(winid)
      return winid == 101 and left or right
    end

    render_latex.setup({ install = { auto = false } })
    attached = {}
    queued = {}

    vim.api.nvim_exec_autocmds("ColorScheme", {})

    vim.api.nvim_list_wins = previous_list_wins
    vim.api.nvim_win_get_config = previous_win_get_config
    vim.api.nvim_win_get_buf = previous_win_get_buf
    renderer.attach = previous_attach
    renderer.queue = previous_queue
    renderer.suppression_status = previous_suppression
    renderer.set_suppressed = previous_set_suppressed
    ui.has_popup_or_floating_windows = previous_has_popup
    vim.fn.getcmdtype = previous_getcmdtype

    table.sort(attached)
    table.sort(queued)
    assert.are.same({ left, right }, attached)
    assert.are.same({ left, right }, queued)
  end)

  it("uses the lightweight refresh path on WinScrolled", function()
    local previous_scroll = renderer.scroll
    local previous_queue = renderer.queue
    local previous_attach = renderer.attach
    local previous_suppression = renderer.suppression_status
    local previous_set_suppressed = renderer.set_suppressed
    local previous_has_popup = ui.has_popup_or_floating_windows
    local previous_getcmdtype = vim.fn.getcmdtype
    local scrolled = {}
    local queued = {}

    renderer.scroll = function(bufnr)
      scrolled[#scrolled + 1] = bufnr
    end
    renderer.queue = function(bufnr)
      queued[#queued + 1] = bufnr
    end
    renderer.attach = function() end
    renderer.suppression_status = function()
      return { cmdline = false, floating = false }
    end
    renderer.set_suppressed = function() end
    ui.has_popup_or_floating_windows = function()
      return false
    end
    vim.fn.getcmdtype = function()
      return ""
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "markdown"
    render_latex.setup({ install = { auto = false } })

    vim.api.nvim_exec_autocmds("WinScrolled", { buffer = buf, modeline = false })

    renderer.scroll = previous_scroll
    renderer.queue = previous_queue
    renderer.attach = previous_attach
    renderer.suppression_status = previous_suppression
    renderer.set_suppressed = previous_set_suppressed
    ui.has_popup_or_floating_windows = previous_has_popup
    vim.fn.getcmdtype = previous_getcmdtype

    assert.are.same({ buf }, scrolled)
    assert.are.same({}, queued)
  end)

  it("queues visible buffers while floating windows are suppressed", function()
    local previous_queue = renderer.queue
    local previous_attach = renderer.attach
    local previous_suppression = renderer.suppression_status
    local previous_set_suppressed = renderer.set_suppressed
    local previous_has_popup = ui.has_popup_or_floating_windows
    local previous_getcmdtype = vim.fn.getcmdtype
    local queued = {}

    renderer.queue = function(bufnr)
      queued[#queued + 1] = bufnr
    end
    renderer.attach = function() end
    renderer.suppression_status = function()
      return { cmdline = false, floating = true }
    end
    renderer.set_suppressed = function() end
    ui.has_popup_or_floating_windows = function()
      return true
    end
    vim.fn.getcmdtype = function()
      return ""
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "markdown"
    render_latex.setup({ install = { auto = false } })

    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf, modeline = false })

    renderer.queue = previous_queue
    renderer.attach = previous_attach
    renderer.suppression_status = previous_suppression
    renderer.set_suppressed = previous_set_suppressed
    ui.has_popup_or_floating_windows = previous_has_popup
    vim.fn.getcmdtype = previous_getcmdtype

    assert.are.same({ buf }, queued)
  end)
end)

describe("render_latex.ui", function()
  it("detects floating windows independently of cmdline settings", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 10,
      height = 1,
      style = "minimal",
    })

    local ok, detected = pcall(ui.has_popup_or_floating_windows)
    vim.api.nvim_win_close(win, true)

    assert.is_true(ok)
    assert.is_true(detected)
  end)
end)

describe("render_latex.compat", function()
  it("reports required API support", function()
    local status = compat.summary()
    assert.is_table(status)
    assert.is_boolean(status.supported)
    assert.is_table(status.missing)
  end)
end)

describe("render_latex.doctor", function()
  it("builds a diagnostics buffer payload", function()
    local lines = render_latex.doctor_lines()
    local text = table.concat(lines, "\n")

    assert.matches("# render%-latex doctor", text)
    assert.matches("image backend status", text)
    assert.matches("hide on cmdline", text)
    assert.matches("kitty probing", text)
    assert.matches("tmux passthrough", text)
    assert.matches("## render%-markdown.nvim", text)
    assert.matches("status:", text)
    assert.matches("## obsidian.nvim", text)
    assert.matches("The render loop does not inspect other plugins", text)
  end)

  it("includes backend availability in tmux diagnostics", function()
    local previous_open_scratch = util.open_scratch
    local opened
    util.open_scratch = function(lines, filetype)
      opened = { lines = lines, filetype = filetype }
    end

    local ok, err = pcall(render_latex.tmux_check)

    util.open_scratch = previous_open_scratch

    assert.is_true(ok, err)
    local text = table.concat(opened.lines, "\n")
    assert.are.equal("markdown", opened.filetype)
    assert.matches("backend available", text)
    assert.matches("image backend status", text)
    assert.matches("kitty available", text)
    assert.matches("kitty probing", text)
    assert.matches("tmux passthrough", text)
  end)
end)

describe("render_latex.integrations", function()
  it("reports render-markdown as unloaded by default", function()
    local previous = package.loaded["render-markdown"]
    local previous_state = package.loaded["render-markdown.state"]
    package.loaded["render-markdown"] = nil
    package.loaded["render-markdown.state"] = nil

    local status = integrations.status(0).render_markdown

    package.loaded["render-markdown"] = previous
    package.loaded["render-markdown.state"] = previous_state

    assert.is_false(status.loaded)
    assert.are.equal("not loaded", status.status)
    assert.is_nil(status.action)
  end)

  it("detects render-markdown LaTeX conflict when loaded", function()
    local previous = package.loaded["render-markdown"]
    local previous_state = package.loaded["render-markdown.state"]
    package.loaded["render-markdown"] = {}
    package.loaded["render-markdown.state"] = {
      enabled = true,
      get = function()
        return { latex = { enabled = true } }
      end,
    }

    local conflict, status = integrations.render_markdown_conflict(0)

    package.loaded["render-markdown"] = previous
    package.loaded["render-markdown.state"] = previous_state

    assert.is_true(conflict)
    assert.is_true(status.loaded)
    assert.is_true(status.latex_enabled)
    assert.is_true(status.conflict)
    assert.are.equal("conflict detected", status.status)
    assert.are.equal("set render-markdown latex.enabled=false", status.action)
  end)

  it("accepts render-markdown with LaTeX disabled", function()
    local previous = package.loaded["render-markdown"]
    local previous_state = package.loaded["render-markdown.state"]
    package.loaded["render-markdown"] = {}
    package.loaded["render-markdown.state"] = {
      enabled = true,
      get = function()
        return { latex = { enabled = false } }
      end,
    }

    local conflict, status = integrations.render_markdown_conflict(0)

    package.loaded["render-markdown"] = previous
    package.loaded["render-markdown.state"] = previous_state

    assert.is_false(conflict)
    assert.is_false(status.latex_enabled)
    assert.is_false(status.conflict)
    assert.are.equal("compatible; render-markdown LaTeX rendering is disabled", status.status)
    assert.is_nil(status.action)
  end)

  it("reports obsidian as loaded without requiring config changes", function()
    local previous = package.loaded.obsidian
    package.loaded.obsidian = {
      workspace = { name = "test-vault" },
    }

    local status = integrations.status(0).obsidian

    package.loaded.obsidian = previous

    assert.is_true(status.loaded)
    assert.is_true(status.client_available)
    assert.are.equal("test-vault", status.workspace)
    assert.are.equal("compatible; no special render-latex config is required", status.status)
    assert.is_nil(status.action)
  end)
end)

describe("render_latex.image_backend", function()
  local previous_kitty
  local previous_wezterm
  local previous_ghostty
  local previous_term
  local previous_term_program
  local previous_tmux
  local previous_send
  local previous_img
  local previous_executable
  local previous_tmux_option

  before_each(function()
    previous_kitty = vim.env.KITTY_WINDOW_ID
    previous_wezterm = vim.env.WEZTERM_EXECUTABLE
    previous_ghostty = vim.env.GHOSTTY_RESOURCES_DIR
    previous_term = vim.env.TERM
    previous_term_program = vim.env.TERM_PROGRAM
    previous_tmux = vim.env.TMUX
    previous_send = vim.api.nvim_ui_send
    previous_img = vim.ui.img
    previous_executable = vim.fn.executable
    previous_tmux_option = tmux.option
    image_backend.reset_for_tests()
    config.setup()
  end)

  after_each(function()
    vim.env.KITTY_WINDOW_ID = previous_kitty
    vim.env.WEZTERM_EXECUTABLE = previous_wezterm
    vim.env.GHOSTTY_RESOURCES_DIR = previous_ghostty
    vim.env.TERM = previous_term
    vim.env.TERM_PROGRAM = previous_term_program
    vim.env.TMUX = previous_tmux
    vim.api.nvim_ui_send = previous_send
    vim.ui.img = previous_img
    vim.fn.executable = previous_executable
    tmux.option = previous_tmux_option
    image_backend.reset_for_tests()
    config.setup()
  end)

  it("uses explicit nvim backend when available", function()
    vim.ui.img = {
      set = function() end,
      get = function() end,
      del = function() end,
    }
    config.setup({ image = { backend = "nvim" } })

    local backend, name, reason = image_backend.get()

    assert.is_truthy(backend)
    assert.are.equal("nvim", name)
    assert.is_nil(reason)
  end)

  it("reports unavailable explicit nvim backend without vim.ui.img", function()
    vim.ui.img = {}
    config.setup({ image = { backend = "nvim" } })

    local backend, name, reason = image_backend.get()

    assert.is_nil(backend)
    assert.are.equal("nvim", name)
    assert.are.equal("vim.ui.img is unavailable", reason)
  end)

  it("prefers kitty in tmux auto mode when passthrough is available", function()
    vim.ui.img = {
      set = function() end,
      get = function() end,
      del = function() end,
    }
    config.setup({ image = { backend = "auto" } })
    vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
    vim.env.KITTY_WINDOW_ID = "1"
    vim.fn.executable = function(name)
      return name == "tmux" and 1 or previous_executable(name)
    end
    tmux.option = function()
      return "on"
    end

    local backend, name, reason = image_backend.get()

    assert.is_truthy(backend)
    assert.are.equal("kitty", name)
    assert.is_nil(reason)
  end)

  it("falls back to nvim in tmux auto mode when kitty is unavailable", function()
    vim.ui.img = {
      set = function() end,
      get = function() end,
      del = function() end,
    }
    config.setup({ image = { backend = "auto" } })
    vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
    vim.env.KITTY_WINDOW_ID = nil
    vim.env.WEZTERM_EXECUTABLE = nil
    vim.env.GHOSTTY_RESOURCES_DIR = nil
    vim.env.TERM = "screen-256color"
    vim.env.TERM_PROGRAM = nil
    vim.fn.executable = function(name)
      return name == "tmux" and 1 or previous_executable(name)
    end
    tmux.option = function()
      return "off"
    end

    local backend, name, reason = image_backend.get()

    assert.is_truthy(backend)
    assert.are.equal("nvim", name)
    assert.is_nil(reason)
  end)

  it("requires tmux passthrough and a known outer terminal for kitty", function()
    vim.ui.img = {}
    config.setup({ image = { backend = "kitty" } })
    vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
    vim.env.KITTY_WINDOW_ID = nil
    vim.env.WEZTERM_EXECUTABLE = nil
    vim.env.GHOSTTY_RESOURCES_DIR = nil
    vim.env.TERM = "screen-256color"
    vim.env.TERM_PROGRAM = nil
    vim.fn.executable = function(name)
      return name == "tmux" and 1 or previous_executable(name)
    end
    tmux.option = function()
      return "off"
    end

    local backend, _, reason = image_backend.get()
    assert.is_nil(backend)
    assert.are.equal("tmux allow-passthrough is not enabled", reason)

    image_backend.reset_for_tests()
    tmux.option = function()
      return "on"
    end

    config.setup({ image = { backend = "auto" } })
    vim.env.KITTY_WINDOW_ID = ""
    backend, _, reason = image_backend.get()
    assert.is_nil(backend)
    assert.are.equal(
      "tmux outer terminal is not known to support Kitty graphics; set image.backend = 'kitty' to force it",
      reason
    )

    config.setup({ image = { backend = "kitty" } })
    image_backend.reset_for_tests()
    backend, _, reason = image_backend.get()
    assert.is_truthy(backend)
    assert.is_nil(reason)

    vim.env.KITTY_WINDOW_ID = "1"
    image_backend.reset_for_tests()
    backend, _, reason = image_backend.get()

    assert.is_truthy(backend)
    assert.is_nil(reason)
  end)

  it("reports unavailable explicit kitty backend without terminal support", function()
    config.setup({ image = { backend = "kitty" } })
    vim.env.KITTY_WINDOW_ID = nil
    vim.env.WEZTERM_EXECUTABLE = nil
    vim.env.GHOSTTY_RESOURCES_DIR = nil
    vim.env.TERM = "xterm-256color"
    vim.env.TERM_PROGRAM = nil
    vim.env.TMUX = nil

    local backend, _, reason = image_backend.get()

    assert.is_nil(backend)
    assert.is_truthy(reason)
  end)

  it("does not probe kitty support when nvim_ui_send is unavailable", function()
    config.setup({ image = { backend = "kitty" } })
    vim.env.KITTY_WINDOW_ID = nil
    vim.env.WEZTERM_EXECUTABLE = nil
    vim.env.GHOSTTY_RESOURCES_DIR = nil
    vim.env.TERM = "xterm-256color"
    vim.env.TERM_PROGRAM = nil
    vim.env.TMUX = nil
    vim.api.nvim_ui_send = nil

    local backend, _, reason = image_backend.get()
    local status = image_backend.status()

    assert.is_nil(backend)
    assert.are.equal("kitty image protocol is not available in this terminal", reason)
    assert.is_false(status.kitty_probing)
    assert.is_false(status.kitty_available)
  end)

  it("treats Ghostty as a known kitty-compatible terminal", function()
    config.setup({ image = { backend = "kitty" } })
    vim.env.KITTY_WINDOW_ID = nil
    vim.env.WEZTERM_EXECUTABLE = nil
    vim.env.GHOSTTY_RESOURCES_DIR = nil
    vim.env.TERM = "xterm-ghostty"
    vim.env.TERM_PROGRAM = nil
    vim.env.TMUX = nil
    vim.api.nvim_ui_send = nil

    local backend, name, reason = image_backend.get()
    local status = image_backend.status()

    assert.is_truthy(backend)
    assert.are.equal("kitty", name)
    assert.is_nil(reason)
    assert.is_true(status.kitty_available)
    assert.is_false(status.kitty_probing)
  end)

  it("detects Ghostty from TERM_PROGRAM", function()
    config.setup({ image = { backend = "kitty" } })
    vim.env.KITTY_WINDOW_ID = nil
    vim.env.WEZTERM_EXECUTABLE = nil
    vim.env.GHOSTTY_RESOURCES_DIR = nil
    vim.env.TERM = "xterm-256color"
    vim.env.TERM_PROGRAM = "ghostty"
    vim.env.TMUX = nil
    vim.api.nvim_ui_send = nil

    local backend = image_backend.get()

    assert.is_truthy(backend)
  end)

  it("probes kitty support for unknown compatible terminals", function()
    local sent = {}
    config.setup({ image = { backend = "kitty" } })
    vim.env.KITTY_WINDOW_ID = nil
    vim.env.WEZTERM_EXECUTABLE = nil
    vim.env.GHOSTTY_RESOURCES_DIR = nil
    vim.env.TERM = "xterm-direct"
    vim.env.TERM_PROGRAM = "unknown"
    vim.env.TMUX = nil
    vim.api.nvim_ui_send = function(sequence)
      sent[#sent + 1] = sequence
    end

    local backend, _, reason = image_backend.get()
    local status = image_backend.status()

    assert.is_nil(backend)
    assert.is_truthy(reason)
    assert.is_true(status.kitty_probing)
    assert.are.equal(1, #sent)
    assert.is_truthy(sent[1]:match("\027_Gi=%d+,s=1,v=1,a=q,t=d,f=24;AAAA\027\\\027%[c"))
  end)

  it("caches kitty support after a successful protocol response", function()
    local sent = {}
    config.setup({ image = { backend = "kitty" } })
    vim.env.KITTY_WINDOW_ID = nil
    vim.env.WEZTERM_EXECUTABLE = nil
    vim.env.GHOSTTY_RESOURCES_DIR = nil
    vim.env.TERM = "xterm-direct"
    vim.env.TERM_PROGRAM = "unknown"
    vim.env.TMUX = nil
    vim.api.nvim_ui_send = function(sequence)
      sent[#sent + 1] = sequence
    end

    local backend = image_backend.get()
    local request_id = sent[1]:match("\027_Gi=(%d+),")
    vim.api.nvim_exec_autocmds("TermResponse", {
      data = { sequence = ("\027_Gi=%s;OK\027\\"):format(request_id) },
    })

    backend = image_backend.get()

    assert.is_truthy(backend)
    assert.is_false(image_backend.status().kitty_probing)
    assert.are.equal(1, #sent)
  end)

  it("keeps probing when DA1 arrives before the kitty response", function()
    local sent = {}
    config.setup({ image = { backend = "kitty" } })
    vim.env.KITTY_WINDOW_ID = nil
    vim.env.WEZTERM_EXECUTABLE = nil
    vim.env.GHOSTTY_RESOURCES_DIR = nil
    vim.env.TERM = "xterm-direct"
    vim.env.TERM_PROGRAM = "unknown"
    vim.env.TMUX = nil
    vim.api.nvim_ui_send = function(sequence)
      sent[#sent + 1] = sequence
    end

    image_backend.get()
    local request_id = sent[1]:match("\027_Gi=(%d+),")
    vim.api.nvim_exec_autocmds("TermResponse", {
      data = { sequence = "\027[?62;c" },
    })

    local backend, _, reason = image_backend.get()

    assert.is_nil(backend)
    assert.is_truthy(reason)
    assert.is_true(image_backend.status().kitty_probing)
    assert.are.equal(1, #sent)

    vim.api.nvim_exec_autocmds("TermResponse", {
      data = { sequence = ("\027_Gi=%s;OK\027\\"):format(request_id) },
    })

    backend = image_backend.get()
    assert.is_truthy(backend)
    assert.is_false(image_backend.status().kitty_probing)
  end)
end)

describe("render_latex.image_backends.kitty", function()
  it("batches placement and deletion updates into one ui send", function()
    local previous_send = vim.api.nvim_ui_send
    local previous_tmux = vim.env.TMUX
    local previous_count = vim.env.TMUX_NEST_COUNT
    local sent = {}

    package.loaded["render_latex.image_backends.kitty"] = nil
    local kitty = require("render_latex.image_backends.kitty")

    vim.api.nvim_ui_send = function(data)
      sent[#sent + 1] = data
    end
    vim.env.TMUX = nil
    vim.env.TMUX_NEST_COUNT = nil

    local id = kitty.set("png", { row = 1, col = 1, width = 2, height = 2 })
    assert.are.equal(2, #sent)

    kitty.begin_batch()
    kitty.set(id, { row = 2, col = 3, width = 2, height = 2 })
    kitty.del(id)
    assert.are.equal(2, #sent)
    kitty.flush_batch()

    vim.api.nvim_ui_send = previous_send
    vim.env.TMUX = previous_tmux
    vim.env.TMUX_NEST_COUNT = previous_count

    assert.are.equal(3, #sent)
    assert.is_truthy(sent[3]:find("a=p", 1, true))
    assert.is_truthy(sent[3]:find("a=d", 1, true))
  end)
end)

describe("render_latex.install", function()
  it("resolves configured worker path", function()
    local previous_executable = vim.fn.executable
    vim.fn.executable = function(path)
      return path == "/tmp/render-latex-worker-test" and 1 or 0
    end

    config.setup({ worker = { bin = "/tmp/render-latex-worker-test" } })
    assert.are.equal("/tmp/render-latex-worker-test", install.ensure_worker_path())

    vim.fn.executable = previous_executable
    config.setup()
  end)

  it("reports configured worker paths that are not executable", function()
    local previous_executable = vim.fn.executable
    vim.fn.executable = function()
      return 0
    end

    config.setup({ worker = { bin = "/tmp/missing-render-latex-worker" } })
    local status = install.status()

    vim.fn.executable = previous_executable
    config.setup()

    assert.is_nil(status.path)
    assert.are.equal("config", status.source)
    assert.matches("not executable", status.path_error)
  end)
end)

describe("render_latex.worker", function()
  it("times out pending requests so renders can retry", function()
    local previous_spawn = vim.uv.spawn
    local previous_pipe = vim.uv.new_pipe
    local previous_executable = vim.fn.executable
    local callback_err

    local function fake_handle()
      local closed = false
      return {
        is_closing = function()
          return closed
        end,
        close = function()
          closed = true
        end,
        read_start = function() end,
        write = function(_, _, callback)
          if callback ~= nil then
            callback(nil)
          end
        end,
      }
    end

    vim.fn.executable = function(path)
      return path == "/tmp/render-latex-worker-timeout" and 1 or 0
    end
    vim.uv.new_pipe = function()
      return fake_handle()
    end
    vim.uv.spawn = function()
      return fake_handle(), 123
    end
    config.setup({ worker = { bin = "/tmp/render-latex-worker-timeout" } })
    worker.set_request_timeout_for_tests(1)

    worker.request("render_batch", { items = {} }, function(_, err)
      callback_err = err
    end)
    vim.wait(100, function()
      return callback_err ~= nil
    end)

    worker.set_request_timeout_for_tests(30000)
    worker.stop()
    config.setup()
    vim.uv.spawn = previous_spawn
    vim.uv.new_pipe = previous_pipe
    vim.fn.executable = previous_executable

    assert.are.equal("worker request timed out", callback_err)
    assert.is_false(worker.status().running)
    assert.are.equal(0, worker.status().pending)
  end)
end)

describe("render_latex.renderer", function()
  it("resolves automatic render options", function()
    local opts = renderer.resolved_options()
    assert.is_truthy(opts.foreground)
    assert.is_truthy(opts.foreground_source)
    assert.is_true(opts.font_size > 0)
  end)

  it("uses quote foreground for quoted display equations", function()
    config.setup({ render = { foreground = nil, match_text_color = true } })
    local previous_quote = vim.api.nvim_get_hl(0, { name = "@markup.quote", link = false })
    local previous_math = vim.api.nvim_get_hl(0, { name = "@markup.math", link = false })
    vim.api.nvim_set_hl(0, "@markup.quote", { fg = "#123456" })
    vim.api.nvim_set_hl(0, "@markup.math", { fg = "#abcdef" })

    local ok, err = pcall(function()
      local quoted = renderer.resolved_options({ quoted = true })
      local regular = renderer.resolved_options({ quoted = false })

      assert.are.equal("#123456", quoted.foreground)
      assert.are.equal("@markup.quote", quoted.foreground_source)
      assert.are.equal("#abcdef", regular.foreground)
      assert.are.equal("@markup.math", regular.foreground_source)
    end)

    vim.api.nvim_set_hl(0, "@markup.quote", previous_quote)
    vim.api.nvim_set_hl(0, "@markup.math", previous_math)
    if not ok then
      error(err)
    end
  end)

  it("rerenders visible equations when highlight colors change", function()
    config.setup({ render = { foreground = nil, match_text_color = true } })
    local previous_img = vim.ui.img
    local previous_backend_status = image_backend.status
    local previous_backend_get = image_backend.get
    local previous_request_batch = worker.request_batch
    local previous_detect_scan = detect.scan
    local previous_viewport_range = viewport.viewport_range
    local previous_visible_text_bounds = viewport.visible_text_bounds
    local previous_readblob = vim.fn.readblob
    local previous_math = vim.api.nvim_get_hl(0, { name = "@markup.math", link = false })
    local request_count = 0

    local backend = {
      set = function()
        return 1
      end,
      del = function() end,
      get = function()
        return nil
      end,
    }

    vim.ui.img = {
      set = function()
        return 1
      end,
      get = function()
        return nil
      end,
      del = function() end,
    }
    image_backend.status = function()
      return { available = true, name = "nvim" }
    end
    image_backend.get = function()
      return backend, "nvim"
    end
    worker.request_batch = function(_, callback)
      request_count = request_count + 1
      callback({
        {
          error = nil,
          result = {
            width_px = 10,
            height_px = 10,
            png_path = "/tmp/render-latex-theme-test.png",
            cache_key = "theme-test-" .. request_count,
          },
        },
      }, nil)
    end
    vim.fn.readblob = function()
      return "png"
    end
    detect.scan = function()
      return {
        {
          key = "display:1:3",
          start_row = 0,
          end_row = 2,
          text = "x^2",
          quoted = false,
        },
      }
    end
    viewport.viewport_range = function()
      return 0, 3
    end
    viewport.visible_text_bounds = function()
      return 1, 20
    end

    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "$$", "x^2", "$$", "after" })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })

    renderer.set_suppressed("cmdline", false)
    renderer.set_suppressed("floating", false)
    renderer.attach(buf)
    vim.api.nvim_set_hl(0, "@markup.math", { fg = "#111111" })
    renderer.render(buf)
    vim.wait(100, function()
      return request_count == 1
    end)

    vim.api.nvim_set_hl(0, "@markup.math", { fg = "#eeeeee" })
    renderer.render(buf)
    vim.wait(100, function()
      return request_count == 2
    end)

    vim.api.nvim_set_hl(0, "@markup.math", previous_math)
    worker.request_batch = previous_request_batch
    detect.scan = previous_detect_scan
    image_backend.status = previous_backend_status
    image_backend.get = previous_backend_get
    vim.fn.readblob = previous_readblob
    vim.ui.img = previous_img

    assert.are.equal(2, request_count)
  end)

  it("coalesces repeated scroll refresh requests", function()
    local previous_refresh_visible = renderer.refresh_visible
    local calls = 0
    local buf = vim.api.nvim_create_buf(true, true)

    renderer.refresh_visible = function(target)
      assert.are.equal(buf, target)
      calls = calls + 1
    end

    renderer.scroll(buf)
    renderer.scroll(buf)
    renderer.scroll(buf)
    vim.wait(100, function()
      return calls == 1
    end)
    renderer.refresh_visible = previous_refresh_visible

    assert.are.equal(1, calls)
  end)

  it("tracks dirty edits for focused equations", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "$$", "x^2", "$$" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    renderer.render(buf)
    assert.has_no.errors(function()
      renderer.on_text_changed(buf)
    end)
  end)

  it("does not repeatedly scan buffers that contain no display equations", function()
    config.setup({ render_modes = { vim.api.nvim_get_mode().mode }, render = { inline = false } })
    local previous_detect_scan = detect.scan
    local previous_backend_status = image_backend.status
    local previous_viewport_range = viewport.viewport_range
    local scan_count = 0

    detect.scan = function()
      scan_count = scan_count + 1
      return {}
    end
    image_backend.status = function()
      return { available = true, name = "test" }
    end
    viewport.viewport_range = function()
      return 0, 3
    end

    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "plain text", "more text" })

    renderer.set_suppressed("cmdline", false)
    renderer.set_suppressed("floating", false)
    renderer.render(buf)
    renderer.render(buf)

    detect.scan = previous_detect_scan
    image_backend.status = previous_backend_status
    viewport.viewport_range = previous_viewport_range

    assert.are.equal(1, scan_count)
  end)

  it("renders a focused equation in normal mode on first view", function()
    config.setup({ render_modes = { vim.api.nvim_get_mode().mode } })
    local previous_backend_status = image_backend.status
    local previous_backend_get = image_backend.get
    local previous_request_batch = worker.request_batch
    local previous_viewport_range = viewport.viewport_range
    local request_count = 0

    local backend = {
      del = function() end,
      set = function()
        return 1
      end,
    }
    image_backend.status = function()
      return { available = true, name = "test" }
    end
    image_backend.get = function()
      return backend, "test"
    end
    worker.request_batch = function(items, callback)
      request_count = request_count + 1
      assert.are.equal("x^2", items[1].formula)
      callback(nil, "worker installing")
    end
    viewport.viewport_range = function()
      return 0, 3
    end

    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "$$", "x^2", "$$" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    renderer.set_suppressed("cmdline", false)
    renderer.set_suppressed("floating", false)
    renderer.attach(buf)
    renderer.render(buf)

    worker.request_batch = previous_request_batch
    viewport.viewport_range = previous_viewport_range
    image_backend.status = previous_backend_status
    image_backend.get = previous_backend_get

    assert.are.equal(1, request_count)
  end)

  it("can inspect and toggle the current equation", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "$$", "x^2", "$$" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    renderer.attach(buf)
    renderer.render(buf)

    local equation = renderer.current_equation(buf)
    assert.is_truthy(equation)

    local debug_info = renderer.debug_current(buf)
    assert.is_truthy(debug_info)

    local ok, toggled = renderer.toggle_current(buf)
    assert.is_true(ok)
    assert.is_true(toggled)

    ok = renderer.rerender_current(buf)
    assert.is_true(ok)
  end)

  it("can return the current equation source", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "$$", "x^2", "$$" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    renderer.attach(buf)
    local source = renderer.current_equation_source(buf)
    assert.is_truthy(source)
    assert.are.equal("$$\nx^2\n$$", source.text)
  end)

  it("tracks suppression state", function()
    renderer.set_suppressed("cmdline", true)
    local state = renderer.suppression_status()
    assert.is_true(state.cmdline)
    renderer.set_suppressed("cmdline", false)
  end)

  it("does not repeatedly clear images when suppression state is unchanged", function()
    local previous_backend_get = image_backend.get
    local delete_count = 0

    image_backend.get = function()
      return {
        del = function()
          delete_count = delete_count + 1
        end,
      },
        "test"
    end

    renderer.set_suppressed("floating", false)
    renderer.set_suppressed("floating", true)
    renderer.set_suppressed("floating", true)
    renderer.set_suppressed("floating", false)
    image_backend.get = previous_backend_get

    assert.are.equal(1, delete_count)
  end)

  it("requests equation renders while floating windows are suppressed", function()
    config.setup({ render_modes = { vim.api.nvim_get_mode().mode } })
    local previous_backend_status = image_backend.status
    local previous_backend_get = image_backend.get
    local previous_request_batch = worker.request_batch
    local previous_viewport_range = viewport.viewport_range
    local request_count = 0
    local requested_items

    local backend = {
      del = function() end,
      set = function()
        return 1
      end,
    }
    image_backend.status = function()
      return { available = true, name = "test" }
    end
    image_backend.get = function()
      return backend, "test"
    end
    worker.request_batch = function(items, callback)
      request_count = request_count + 1
      requested_items = items
      callback(nil, "worker installing")
    end
    viewport.viewport_range = function()
      return 0, 3
    end

    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "$$", "x^2", "$$", "after" })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })

    renderer.set_suppressed("cmdline", false)
    renderer.set_suppressed("floating", true)
    renderer.attach(buf)
    renderer.render(buf)
    renderer.set_suppressed("floating", false)

    worker.request_batch = previous_request_batch
    viewport.viewport_range = previous_viewport_range
    image_backend.status = previous_backend_status
    image_backend.get = previous_backend_get

    assert.are.equal(1, request_count)
    assert.are.equal(1, #requested_items)
    assert.are.equal("x^2", requested_items[1].formula)
  end)

  it("does not place existing equation images while floating windows are suppressed", function()
    config.setup({ render_modes = { vim.api.nvim_get_mode().mode } })
    local previous_backend_status = image_backend.status
    local previous_backend_get = image_backend.get
    local previous_request_batch = worker.request_batch
    local previous_detect_scan = detect.scan
    local previous_viewport_range = viewport.viewport_range
    local previous_visible_text_bounds = viewport.visible_text_bounds
    local previous_readblob = vim.fn.readblob
    local set_count = 0
    local del_count = 0

    local backend = {
      del = function()
        del_count = del_count + 1
      end,
      set = function()
        set_count = set_count + 1
        return set_count
      end,
    }
    image_backend.status = function()
      return { available = true, name = "test" }
    end
    image_backend.get = function()
      return backend, "test"
    end
    worker.request_batch = function(_, callback)
      callback({
        {
          error = nil,
          result = {
            width_px = 10,
            height_px = 10,
            png_path = "/tmp/render-latex-floating-refresh-test.png",
            cache_key = "floating-refresh-test",
          },
        },
      }, nil)
    end
    detect.scan = function()
      return {
        {
          key = "display:1:3",
          start_row = 0,
          end_row = 2,
          text = "x^2",
          quoted = false,
        },
      }
    end
    viewport.viewport_range = function()
      return 0, 3
    end
    viewport.visible_text_bounds = function()
      return 1, 20
    end
    vim.fn.readblob = function()
      return "png"
    end

    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "$$", "x^2", "$$", "after" })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })

    renderer.set_suppressed("cmdline", false)
    renderer.set_suppressed("floating", false)
    renderer.attach(buf)
    renderer.render(buf)
    vim.wait(100, function()
      return set_count == 1
    end)

    set_count = 0
    del_count = 0
    renderer.set_suppressed("floating", true)
    renderer.refresh_visible(buf)
    renderer.set_suppressed("floating", false)

    worker.request_batch = previous_request_batch
    detect.scan = previous_detect_scan
    viewport.viewport_range = previous_viewport_range
    viewport.visible_text_bounds = previous_visible_text_bounds
    image_backend.status = previous_backend_status
    image_backend.get = previous_backend_get
    vim.fn.readblob = previous_readblob

    assert.are.equal(0, set_count)
    assert.is_true(del_count > 0)
  end)

  it("preserves equation state in unsupported transient modes", function()
    config.setup({ render_modes = { "__never__" } })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "$$", "x^2", "$$" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    renderer.attach(buf)
    local ok, toggled = renderer.toggle_current(buf)
    assert.is_true(ok)
    assert.is_true(toggled)

    renderer.render(buf)
    local debug_info = renderer.debug_current(buf)

    assert.is_truthy(debug_info)
    assert.is_true(debug_info.manual_raw)
  end)

  it("does not repeatedly request failed equation renders", function()
    config.setup({ render_modes = { vim.api.nvim_get_mode().mode } })
    local previous_img = vim.ui.img
    local previous_backend_status = image_backend.status
    local previous_request_batch = worker.request_batch
    local previous_visible_equations = viewport.visible_equations
    local previous_warn = util.warn
    local request_count = 0
    local warn_count = 0

    vim.ui.img = {
      set = function()
        return 1
      end,
      del = function() end,
    }
    image_backend.status = function()
      return { available = true, name = "test" }
    end
    worker.request_batch = function(_, callback)
      request_count = request_count + 1
      callback({ { error = { message = "parse error" }, result = nil } }, nil)
    end
    viewport.visible_equations = function(_, indexed_equations)
      return indexed_equations
    end
    util.warn = function()
      warn_count = warn_count + 1
    end

    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "$$", "\\bad", "$$", "after" })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })

    renderer.set_suppressed("cmdline", false)
    renderer.set_suppressed("floating", false)
    renderer.attach(buf)
    renderer.render(buf)
    renderer.render(buf)

    worker.request_batch = previous_request_batch
    viewport.visible_equations = previous_visible_equations
    image_backend.status = previous_backend_status
    util.warn = previous_warn
    vim.ui.img = previous_img

    assert.are.equal(1, request_count)
    assert.are.equal(1, warn_count)
  end)
end)

describe("render_latex.viewport", function()
  it("computes each window range once when filtering visible equations", function()
    local previous_win_findbuf = vim.fn.win_findbuf
    local previous_win_is_valid = vim.api.nvim_win_is_valid
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three" })
    vim.fn.win_findbuf = function(target)
      if target == buf then
        return { 101 }
      end
      return {}
    end
    vim.api.nvim_win_is_valid = function(winid)
      return winid == 101
    end

    local previous_viewport_range = viewport.viewport_range
    local calls = 0
    viewport.viewport_range = function()
      calls = calls + 1
      return 0, 1
    end

    local ok, ranges = pcall(viewport.viewport_ranges, buf, {}, 0)
    viewport.viewport_range = previous_viewport_range
    vim.fn.win_findbuf = previous_win_findbuf
    vim.api.nvim_win_is_valid = previous_win_is_valid

    assert.is_true(ok)
    assert.are.equal(1, calls)
    assert.are.equal(1, #ranges)
    assert.are.same({ top = 0, bottom = 1 }, ranges[1])
  end)

  it("hides equations inside closed folds from visible equation filtering", function()
    local previous_win_findbuf = vim.fn.win_findbuf
    local previous_win_is_valid = vim.api.nvim_win_is_valid
    local previous_viewport_range = viewport.viewport_range
    local previous_fold_closed = viewport.fold_closed
    local buf = vim.api.nvim_create_buf(false, true)

    vim.fn.win_findbuf = function(target)
      if target == buf then
        return { 101 }
      end
      return {}
    end
    vim.api.nvim_win_is_valid = function(winid)
      return winid == 101
    end
    viewport.viewport_range = function()
      return 0, 10
    end
    viewport.fold_closed = function(equation)
      return equation.key == "folded"
    end

    local visible = viewport.visible_equations(buf, {
      { start_row = 1, end_row = 3, key = "folded" },
      { start_row = 5, end_row = 6, key = "visible" },
    }, {}, 0)

    vim.fn.win_findbuf = previous_win_findbuf
    vim.api.nvim_win_is_valid = previous_win_is_valid
    viewport.viewport_range = previous_viewport_range
    viewport.fold_closed = previous_fold_closed

    assert.are.equal(1, #visible)
    assert.are.equal("visible", visible[1].key)
  end)
end)
