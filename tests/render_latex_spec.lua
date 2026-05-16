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
local ui = require("render_latex.ui")
local util = require("render_latex.util")
local viewport = require("render_latex.viewport")
local worker = require("render_latex.worker")

describe("render_latex.detect", function()
  it("finds $$ display math blocks", function()
    local buf = vim.api.nvim_create_buf(true, true)
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
    local buf = vim.api.nvim_create_buf(false, true)
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
    local buf = vim.api.nvim_create_buf(false, true)
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
  it("normalizes supported platform names", function()
    assert.are.equal("linux-x64", install._system_key_from_uname("Linux", "x86_64"))
    assert.is_nil(install._system_key_from_uname("Linux", "aarch64"))
    assert.are.equal("macos-x64", install._system_key_from_uname("Darwin", "x86_64"))
    assert.are.equal("macos-arm64", install._system_key_from_uname("Darwin", "arm64"))
    assert.are.equal("windows-x64", install._system_key_from_uname("Windows_NT", "AMD64"))
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
end)

describe("render_latex.setup", function()
  it("can be called repeatedly without duplicating autocmds", function()
    render_latex.setup({ install = { auto = false }, render = { inline = "highlight" } })
    local first = #vim.api.nvim_get_autocmds({ group = config.augroup })

    render_latex.setup({ install = { auto = false }, render = { inline = "conceal" } })
    local second = #vim.api.nvim_get_autocmds({ group = config.augroup })

    assert.are.equal(first, second)
    assert.are.equal("conceal", config.render.inline)
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
    assert.matches("hide on cmdline", text)
    assert.matches("## render%-markdown.nvim", text)
    assert.matches("## obsidian.nvim", text)
    assert.matches("The render loop does not inspect other plugins", text)
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
    assert.is_truthy(status.recommendation)
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
    assert.is_truthy(status.recommendation)
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
    assert.is_truthy(status.recommendation)
  end)
end)

describe("render_latex.image_backend", function()
  it("uses explicit nvim backend when available", function()
    local previous_img = vim.ui.img
    vim.ui.img = {
      set = function() end,
      get = function() end,
      del = function() end,
    }
    config.setup({ image = { backend = "nvim" } })

    local backend, name, reason = image_backend.get()

    config.setup()
    vim.ui.img = previous_img

    assert.is_truthy(backend)
    assert.are.equal("nvim", name)
    assert.is_nil(reason)
  end)

  it("reports unavailable explicit nvim backend without vim.ui.img", function()
    local previous_img = vim.ui.img
    vim.ui.img = {}
    config.setup({ image = { backend = "nvim" } })

    local backend, name, reason = image_backend.get()

    config.setup()
    vim.ui.img = previous_img

    assert.is_nil(backend)
    assert.are.equal("nvim", name)
    assert.are.equal("vim.ui.img is unavailable", reason)
  end)

  it("reports unavailable explicit kitty backend without terminal support", function()
    config.setup({ image = { backend = "kitty" } })
    local previous_kitty = vim.env.KITTY_WINDOW_ID
    local previous_wezterm = vim.env.WEZTERM_EXECUTABLE
    local previous_term = vim.env.TERM
    local previous_tmux = vim.env.TMUX
    vim.env.KITTY_WINDOW_ID = nil
    vim.env.WEZTERM_EXECUTABLE = nil
    vim.env.TERM = "xterm-256color"
    vim.env.TMUX = nil

    local backend, _, reason = image_backend.get()

    vim.env.KITTY_WINDOW_ID = previous_kitty
    vim.env.WEZTERM_EXECUTABLE = previous_wezterm
    vim.env.TERM = previous_term
    vim.env.TMUX = previous_tmux
    config.setup()

    assert.is_nil(backend)
    assert.is_truthy(reason)
  end)
end)

describe("render_latex.install", function()
  it("resolves configured worker path", function()
    config.setup({ worker = { bin = "/tmp/render-latex-worker-test" } })
    assert.are.equal("/tmp/render-latex-worker-test", install.ensure_worker_path())
    config.setup()
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
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three" })

    local previous_viewport_range = viewport.viewport_range
    local calls = 0
    viewport.viewport_range = function()
      calls = calls + 1
      return 0, 1
    end

    local equations = {}
    for index = 1, 50 do
      equations[index] = { start_row = index - 1, end_row = index - 1 }
    end
    local ok, visible = pcall(viewport.visible_equations, buf, equations, {}, 0)
    viewport.viewport_range = previous_viewport_range

    assert.is_true(ok)
    assert.are.equal(1, calls)
    assert.are.equal(2, #visible)
  end)
end)
