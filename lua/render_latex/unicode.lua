-- Converts inline LaTeX math to Unicode text for the conceal fallback.
--
-- `M.replacements` splits a formula into top-level tokens and returns the ones whose Unicode form
-- differs from their source. Each replacement must fit in its source range, one output character
-- per source character, because conceal marks can show at most one character each.

local M = {}

local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

local function utf8_encode(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return string.char(
      0xE0 + math.floor(cp / 0x1000),
      0x80 + math.floor(cp / 0x40) % 0x40,
      0x80 + cp % 0x40
    )
  end
  return string.char(
    0xF0 + math.floor(cp / 0x40000),
    0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40,
    0x80 + cp % 0x40
  )
end

local function codepoint(ch)
  local b1, b2, b3, b4 = ch:byte(1, 4)
  b2, b3, b4 = b2 or 0x80, b3 or 0x80, b4 or 0x80
  if b1 < 0x80 then
    return b1
  elseif b1 < 0xE0 then
    return (b1 - 0xC0) * 0x40 + (b2 - 0x80)
  elseif b1 < 0xF0 then
    return (b1 - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80)
  end
  return (b1 - 0xF0) * 0x40000 + (b2 - 0x80) * 0x1000 + (b3 - 0x80) * 0x40 + (b4 - 0x80)
end

local function is_combining(cp)
  return (cp >= 0x300 and cp <= 0x36F)
    or (cp >= 0x1AB0 and cp <= 0x1AFF)
    or (cp >= 0x20D0 and cp <= 0x20FF)
    or (cp >= 0xFE20 and cp <= 0xFE2F)
end

---Splits a string into characters, keeping combining marks with their base character.
---@param s string
---@return string[]
function M.graphemes(s)
  local out = {}
  for ch in s:gmatch(CHAR) do
    if #out > 0 and is_combining(codepoint(ch)) then
      out[#out] = out[#out] .. ch
    else
      out[#out + 1] = ch
    end
  end
  return out
end

---Byte offsets (1-based) where each character of `s` starts.
---@param s string
---@return integer[]
function M.char_starts(s)
  local starts = {}
  local pos = 1
  while pos <= #s do
    starts[#starts + 1] = pos
    local _, e = s:find("^" .. CHAR, pos)
    pos = (e or pos) + 1
  end
  return starts
end

local symbols = {
  -- Greek
  alpha = "α",
  beta = "β",
  gamma = "γ",
  delta = "δ",
  epsilon = "ϵ",
  varepsilon = "ε",
  zeta = "ζ",
  eta = "η",
  theta = "θ",
  vartheta = "ϑ",
  iota = "ι",
  kappa = "κ",
  varkappa = "ϰ",
  lambda = "λ",
  mu = "μ",
  nu = "ν",
  xi = "ξ",
  omicron = "ο",
  pi = "π",
  varpi = "ϖ",
  rho = "ρ",
  varrho = "ϱ",
  sigma = "σ",
  varsigma = "ς",
  tau = "τ",
  upsilon = "υ",
  phi = "ϕ",
  varphi = "φ",
  chi = "χ",
  psi = "ψ",
  omega = "ω",
  digamma = "ϝ",
  Gamma = "Γ",
  Delta = "Δ",
  Theta = "Θ",
  Lambda = "Λ",
  Xi = "Ξ",
  Pi = "Π",
  Sigma = "Σ",
  Upsilon = "Υ",
  Phi = "Φ",
  Psi = "Ψ",
  Omega = "Ω",
  -- Hebrew and letterlike
  aleph = "ℵ",
  beth = "ℶ",
  gimel = "ℷ",
  daleth = "ℸ",
  hbar = "ℏ",
  hslash = "ℏ",
  ell = "ℓ",
  wp = "℘",
  Re = "ℜ",
  Im = "ℑ",
  imath = "ı",
  jmath = "ȷ",
  partial = "∂",
  nabla = "∇",
  infty = "∞",
  emptyset = "∅",
  varnothing = "∅",
  complement = "∁",
  mho = "℧",
  eth = "ð",
  Bbbk = "𝕜",
  -- Binary operators
  pm = "±",
  mp = "∓",
  times = "×",
  div = "÷",
  cdot = "·",
  cdotp = "·",
  ast = "∗",
  star = "⋆",
  circ = "∘",
  bullet = "•",
  oplus = "⊕",
  ominus = "⊖",
  otimes = "⊗",
  oslash = "⊘",
  odot = "⊙",
  cap = "∩",
  cup = "∪",
  sqcap = "⊓",
  sqcup = "⊔",
  uplus = "⊎",
  wedge = "∧",
  vee = "∨",
  setminus = "∖",
  smallsetminus = "∖",
  wr = "≀",
  diamond = "⋄",
  bigtriangleup = "△",
  bigtriangledown = "▽",
  triangleleft = "◁",
  triangleright = "▷",
  lhd = "⊲",
  rhd = "⊳",
  dagger = "†",
  ddagger = "‡",
  dag = "†",
  ddag = "‡",
  amalg = "⨿",
  -- Relations
  equiv = "≡",
  nequiv = "≢",
  ne = "≠",
  neq = "≠",
  le = "≤",
  leq = "≤",
  ge = "≥",
  geq = "≥",
  leqslant = "⩽",
  geqslant = "⩾",
  nleq = "≰",
  ngeq = "≱",
  nless = "≮",
  ngtr = "≯",
  lt = "<",
  gt = ">",
  ll = "≪",
  gg = "≫",
  lll = "⋘",
  ggg = "⋙",
  lesssim = "≲",
  gtrsim = "≳",
  lessgtr = "≶",
  approx = "≈",
  approxeq = "≊",
  sim = "∼",
  nsim = "≁",
  simeq = "≃",
  cong = "≅",
  ncong = "≇",
  asymp = "≍",
  doteq = "≐",
  triangleq = "≜",
  coloneqq = "≔",
  coloneq = "≔",
  eqqcolon = "≕",
  propto = "∝",
  prec = "≺",
  succ = "≻",
  preceq = "⪯",
  succeq = "⪰",
  subset = "⊂",
  supset = "⊃",
  subseteq = "⊆",
  supseteq = "⊇",
  subsetneq = "⊊",
  supsetneq = "⊋",
  nsubseteq = "⊈",
  nsupseteq = "⊉",
  sqsubset = "⊏",
  sqsupset = "⊐",
  sqsubseteq = "⊑",
  sqsupseteq = "⊒",
  ["in"] = "∈",
  notin = "∉",
  ni = "∋",
  owns = "∋",
  vdash = "⊢",
  dashv = "⊣",
  models = "⊨",
  vDash = "⊨",
  Vdash = "⊩",
  perp = "⊥",
  mid = "∣",
  nmid = "∤",
  parallel = "∥",
  nparallel = "∦",
  bowtie = "⋈",
  Join = "⋈",
  smile = "⌣",
  frown = "⌢",
  -- Logic
  forall = "∀",
  exists = "∃",
  nexists = "∄",
  neg = "¬",
  lnot = "¬",
  land = "∧",
  lor = "∨",
  implies = "⇒",
  impliedby = "⇐",
  iff = "⇔",
  top = "⊤",
  bot = "⊥",
  therefore = "∴",
  because = "∵",
  -- Arrows
  to = "→",
  gets = "←",
  rightarrow = "→",
  leftarrow = "←",
  leftrightarrow = "↔",
  Rightarrow = "⇒",
  Leftarrow = "⇐",
  Leftrightarrow = "⇔",
  mapsto = "↦",
  longmapsto = "⟼",
  longrightarrow = "⟶",
  longleftarrow = "⟵",
  longleftrightarrow = "⟷",
  Longrightarrow = "⟹",
  Longleftarrow = "⟸",
  Longleftrightarrow = "⟺",
  uparrow = "↑",
  downarrow = "↓",
  updownarrow = "↕",
  Uparrow = "⇑",
  Downarrow = "⇓",
  Updownarrow = "⇕",
  nearrow = "↗",
  searrow = "↘",
  swarrow = "↙",
  nwarrow = "↖",
  hookrightarrow = "↪",
  hookleftarrow = "↩",
  rightharpoonup = "⇀",
  rightharpoondown = "⇁",
  leftharpoonup = "↼",
  leftharpoondown = "↽",
  rightleftharpoons = "⇌",
  leadsto = "⇝",
  rightsquigarrow = "⇝",
  twoheadrightarrow = "↠",
  rightarrowtail = "↣",
  circlearrowleft = "↺",
  circlearrowright = "↻",
  nrightarrow = "↛",
  nleftarrow = "↚",
  nRightarrow = "⇏",
  nLeftrightarrow = "⇎",
  -- Large operators
  sum = "∑",
  prod = "∏",
  coprod = "∐",
  int = "∫",
  iint = "∬",
  iiint = "∭",
  oint = "∮",
  oiint = "∯",
  bigcup = "⋃",
  bigcap = "⋂",
  bigsqcup = "⨆",
  bigvee = "⋁",
  bigwedge = "⋀",
  bigoplus = "⨁",
  bigotimes = "⨂",
  bigodot = "⨀",
  biguplus = "⨄",
  -- Delimiters
  langle = "⟨",
  rangle = "⟩",
  lceil = "⌈",
  rceil = "⌉",
  lfloor = "⌊",
  rfloor = "⌋",
  vert = "|",
  lvert = "|",
  rvert = "|",
  Vert = "‖",
  lVert = "‖",
  rVert = "‖",
  lbrace = "{",
  rbrace = "}",
  lbrack = "[",
  rbrack = "]",
  backslash = "\\",
  ulcorner = "⌜",
  urcorner = "⌝",
  llcorner = "⌞",
  lrcorner = "⌟",
  llbracket = "⟦",
  rrbracket = "⟧",
  -- Dots
  ldots = "…",
  dots = "…",
  dotsc = "…",
  cdots = "⋯",
  dotsb = "⋯",
  vdots = "⋮",
  ddots = "⋱",
  -- Miscellaneous
  angle = "∠",
  measuredangle = "∡",
  degree = "°",
  prime = "′",
  backprime = "‵",
  triangle = "△",
  square = "□",
  Box = "□",
  blacksquare = "■",
  Diamond = "◇",
  lozenge = "◊",
  checkmark = "✓",
  clubsuit = "♣",
  diamondsuit = "♢",
  heartsuit = "♡",
  spadesuit = "♠",
  flat = "♭",
  natural = "♮",
  sharp = "♯",
  surd = "√",
  bigstar = "★",
  qed = "∎",
  S = "§",
  P = "¶",
  colon = ":",
  bmod = "mod",
  And = "&",
  -- Spacing
  quad = " ",
  qquad = "  ",
  enspace = " ",
  thinspace = " ",
  medspace = " ",
  thickspace = " ",
  negthinspace = "",
  -- Style commands with no visible output
  displaystyle = "",
  textstyle = "",
  scriptstyle = "",
  scriptscriptstyle = "",
  limits = "",
  nolimits = "",
  nonumber = "",
  notag = "",
  mathstrut = "",
  strut = "",
}

local functions = {}
for _, name in ipairs({
  "arccos",
  "arcsin",
  "arctan",
  "arg",
  "cos",
  "cosh",
  "cot",
  "coth",
  "csc",
  "deg",
  "det",
  "dim",
  "exp",
  "gcd",
  "hom",
  "inf",
  "ker",
  "lg",
  "lim",
  "liminf",
  "limsup",
  "ln",
  "log",
  "max",
  "min",
  "Pr",
  "sec",
  "sin",
  "sinh",
  "sup",
  "tan",
  "tanh",
  "mod",
}) do
  functions[name] = true
end

-- Single-character commands such as `\,` and `\{`.
local escapes = {
  [","] = " ",
  [":"] = " ",
  [";"] = " ",
  [">"] = " ",
  [" "] = " ",
  ["!"] = "",
  ["{"] = "{",
  ["}"] = "}",
  ["%"] = "%",
  ["$"] = "$",
  ["&"] = "&",
  ["#"] = "#",
  ["_"] = "_",
  ["|"] = "‖",
  ["\\"] = " ",
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
  ["−"] = "⁻",
  ["="] = "⁼",
  ["("] = "⁽",
  [")"] = "⁾",
  a = "ᵃ",
  b = "ᵇ",
  c = "ᶜ",
  d = "ᵈ",
  e = "ᵉ",
  f = "ᶠ",
  g = "ᵍ",
  h = "ʰ",
  i = "ⁱ",
  j = "ʲ",
  k = "ᵏ",
  l = "ˡ",
  m = "ᵐ",
  n = "ⁿ",
  o = "ᵒ",
  p = "ᵖ",
  r = "ʳ",
  s = "ˢ",
  t = "ᵗ",
  u = "ᵘ",
  v = "ᵛ",
  w = "ʷ",
  x = "ˣ",
  y = "ʸ",
  z = "ᶻ",
  A = "ᴬ",
  B = "ᴮ",
  D = "ᴰ",
  E = "ᴱ",
  G = "ᴳ",
  H = "ᴴ",
  I = "ᴵ",
  J = "ᴶ",
  K = "ᴷ",
  L = "ᴸ",
  M = "ᴹ",
  N = "ᴺ",
  O = "ᴼ",
  P = "ᴾ",
  R = "ᴿ",
  T = "ᵀ",
  U = "ᵁ",
  V = "ⱽ",
  W = "ᵂ",
  ["α"] = "ᵅ",
  ["β"] = "ᵝ",
  ["γ"] = "ᵞ",
  ["δ"] = "ᵟ",
  ["ε"] = "ᵋ",
  ["ϵ"] = "ᵋ",
  ["θ"] = "ᶿ",
  ["ι"] = "ᶥ",
  ["ϕ"] = "ᵠ",
  ["φ"] = "ᵠ",
  ["χ"] = "ᵡ",
  ["′"] = "′",
  ["∘"] = "°",
  ["°"] = "°",
  ["⊤"] = "ᵀ",
  ["†"] = "†",
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
  ["−"] = "₋",
  ["="] = "₌",
  ["("] = "₍",
  [")"] = "₎",
  [","] = ",",
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
  ["β"] = "ᵦ",
  ["γ"] = "ᵧ",
  ["ρ"] = "ᵨ",
  ["ϕ"] = "ᵩ",
  ["φ"] = "ᵩ",
  ["χ"] = "ᵪ",
}

-- Characters that are already raised or lowered stay as they are in nested scripts.
for _, map in ipairs({ superscripts, subscripts }) do
  for _, mapped in pairs(vim.deepcopy(map)) do
    if map[mapped] == nil then
      map[mapped] = mapped
    end
  end
end

local primes = { "′", "″", "‴", "⁗" }

local vulgar_fractions = {
  ["1/2"] = "½",
  ["1/3"] = "⅓",
  ["2/3"] = "⅔",
  ["1/4"] = "¼",
  ["3/4"] = "¾",
  ["1/5"] = "⅕",
  ["2/5"] = "⅖",
  ["3/5"] = "⅗",
  ["4/5"] = "⅘",
  ["1/6"] = "⅙",
  ["5/6"] = "⅚",
  ["1/7"] = "⅐",
  ["1/8"] = "⅛",
  ["3/8"] = "⅜",
  ["5/8"] = "⅝",
  ["7/8"] = "⅞",
  ["1/9"] = "⅑",
  ["1/10"] = "⅒",
}

local negations = {
  ["="] = "≠",
  ["<"] = "≮",
  [">"] = "≯",
  ["∈"] = "∉",
  ["∋"] = "∌",
  ["⊂"] = "⊄",
  ["⊃"] = "⊅",
  ["⊆"] = "⊈",
  ["⊇"] = "⊉",
  ["≤"] = "≰",
  ["≥"] = "≱",
  ["∼"] = "≁",
  ["≃"] = "≄",
  ["≅"] = "≇",
  ["≈"] = "≉",
  ["≡"] = "≢",
  ["∃"] = "∄",
  ["∣"] = "∤",
  ["∥"] = "∦",
  ["⊢"] = "⊬",
  ["⊨"] = "⊭",
  ["≺"] = "⊀",
  ["≻"] = "⊁",
  ["→"] = "↛",
  ["←"] = "↚",
  ["⇒"] = "⇏",
  ["⇔"] = "⇎",
}

-- Relations with a symbol stacked above them, as written with \overset or \stackrel.
local stacked_equals = {
  def = "≝",
  ["?"] = "≟",
  ["△"] = "≜",
  ["∧"] = "≙",
  ["⋆"] = "≛",
  m = "≞",
}

local accents = {
  hat = "\u{0302}",
  widehat = "\u{0302}",
  check = "\u{030C}",
  tilde = "\u{0303}",
  widetilde = "\u{0303}",
  acute = "\u{0301}",
  grave = "\u{0300}",
  dot = "\u{0307}",
  ddot = "\u{0308}",
  dddot = "\u{20DB}",
  breve = "\u{0306}",
  bar = "\u{0304}",
  overline = "\u{0305}",
  underline = "\u{0332}",
  vec = "\u{20D7}",
  overrightarrow = "\u{20D7}",
  overleftarrow = "\u{20D6}",
  mathring = "\u{030A}",
  cancel = "\u{0338}",
  bcancel = "\u{0338}",
  xcancel = "\u{0338}",
  sout = "\u{0336}",
}

local function alphabet(upper, lower, digits, exceptions)
  local map = {}
  for i = 0, 25 do
    if upper ~= nil then
      map[string.char(65 + i)] = utf8_encode(upper + i)
    end
    if lower ~= nil then
      map[string.char(97 + i)] = utf8_encode(lower + i)
    end
  end
  if digits ~= nil then
    for i = 0, 9 do
      map[tostring(i)] = utf8_encode(digits + i)
    end
  end
  for char, replacement in pairs(exceptions or {}) do
    map[char] = replacement
  end
  return map
end

local bold = alphabet(0x1D400, 0x1D41A, 0x1D7CE)
local double_struck = alphabet(0x1D538, 0x1D552, 0x1D7D8, {
  C = "ℂ",
  H = "ℍ",
  N = "ℕ",
  P = "ℙ",
  Q = "ℚ",
  R = "ℝ",
  Z = "ℤ",
})
local script = alphabet(0x1D49C, 0x1D4B6, nil, {
  B = "ℬ",
  E = "ℰ",
  F = "ℱ",
  H = "ℋ",
  I = "ℐ",
  L = "ℒ",
  M = "ℳ",
  R = "ℛ",
  e = "ℯ",
  g = "ℊ",
  o = "ℴ",
})
local fraktur = alphabet(0x1D504, 0x1D51E, nil, {
  C = "ℭ",
  H = "ℌ",
  I = "ℑ",
  R = "ℜ",
  Z = "ℨ",
})
local sans_serif = alphabet(0x1D5A0, 0x1D5BA, 0x1D7E2)
local monospace = alphabet(0x1D670, 0x1D68A, 0x1D7F6)

-- Font commands: the alphabet to map letters to, and whether the argument is text or math.
local fonts = {
  mathbb = { map = double_struck },
  mathbf = { map = bold },
  boldsymbol = { map = bold },
  bm = { map = bold },
  mathcal = { map = script },
  mathscr = { map = script },
  mathfrak = { map = fraktur },
  mathsf = { map = sans_serif },
  mathtt = { map = monospace },
  mathrm = {},
  mathit = {},
  mathnormal = {},
  mathop = {},
  mathbin = {},
  mathrel = {},
  mathord = {},
  mathopen = {},
  mathclose = {},
  mathpunct = {},
  operatorname = {},
  overbrace = {},
  underbrace = {},
  text = { text = true },
  textrm = { text = true },
  textnormal = { text = true },
  textup = { text = true },
  textit = { text = true },
  textsl = { text = true },
  textmd = { text = true },
  emph = { text = true },
  mbox = { text = true },
  hbox = { text = true },
  textbf = { text = true, map = bold },
  textsf = { text = true, map = sans_serif },
  texttt = { text = true, map = monospace },
}

local sizing = {}
for _, name in ipairs({
  "left",
  "right",
  "middle",
  "big",
  "Big",
  "bigg",
  "Bigg",
  "bigl",
  "bigr",
  "Bigl",
  "Bigr",
  "biggl",
  "biggr",
  "Biggl",
  "Biggr",
  "bigm",
  "Bigm",
  "biggm",
  "Biggm",
}) do
  sizing[name] = true
end

local function map_graphemes(s, map)
  local out = {}
  for _, g in ipairs(M.graphemes(s)) do
    local mapped = map[g]
    if mapped == nil then
      return nil
    end
    out[#out + 1] = mapped
  end
  return table.concat(out)
end

local function map_letters(s, map)
  return (s:gsub(CHAR, function(ch)
    return map[ch]
  end))
end

local function skip_spaces(text, pos)
  return text:find("[^%s]", pos) or #text + 1
end

-- Position of the brace that closes the group opening at `pos`, or nil when it is unbalanced.
local function group_end(text, pos)
  local depth = 0
  local i = pos
  while i <= #text do
    local c = text:sub(i, i)
    if c == "\\" then
      i = i + 2
    else
      if c == "{" then
        depth = depth + 1
      elseif c == "}" then
        depth = depth - 1
        if depth == 0 then
          return i
        end
      end
      i = i + 1
    end
  end
  return nil
end

local OPERATORS =
  { " ", "+", "-", "*", "/", "=", "<", ">", ",", "±", "∓", "×", "÷", "·", "−" }

-- Whether a fraction part or root needs parentheses to keep its meaning when written inline.
local function needs_parens(s)
  if #M.graphemes(s) <= 1 then
    return false
  end
  if s:sub(1, 1) == "(" and s:sub(-1) == ")" then
    local depth = 0
    for i = 1, #s do
      local c = s:sub(i, i)
      if c == "(" then
        depth = depth + 1
      elseif c == ")" then
        depth = depth - 1
        if depth == 0 and i < #s then
          break
        end
      end
      if depth == 0 and i == #s then
        return false
      end
    end
  end
  for _, op in ipairs(OPERATORS) do
    if s:find(op, 1, true) then
      return true
    end
  end
  return false
end

local function wrap(s)
  return needs_parens(s) and ("(" .. s .. ")") or s
end

---@type fun(text: string, pos: integer): string, integer
local convert_token

local function convert(text)
  local out = {}
  local pos = 1
  while pos <= #text do
    local piece, next_pos = convert_token(text, pos)
    out[#out + 1] = piece
    pos = next_pos
  end
  return table.concat(out)
end

-- Reads one command argument: a braced group or a single token.
-- Returns the converted argument, its raw source without braces, and the position after it.
---@return string? converted
---@return string raw
---@return integer next_pos
local function read_argument(text, pos)
  pos = skip_spaces(text, pos)
  local c = text:sub(pos, pos)
  if c == "" or c == "}" then
    return nil, "", pos
  end
  if c == "{" then
    local close = group_end(text, pos)
    if close == nil then
      return nil, "", pos
    end
    local raw = text:sub(pos + 1, close - 1)
    return convert(raw), raw, close + 1
  end
  local piece, next_pos = convert_token(text, pos)
  return piece, text:sub(pos, next_pos - 1), next_pos
end

local function read_optional(text, pos)
  local start = skip_spaces(text, pos)
  if text:sub(start, start) ~= "[" then
    return nil, pos
  end
  local close = text:find("]", start, true)
  if close == nil then
    return nil, pos
  end
  return text:sub(start + 1, close - 1), close + 1
end

local function script_text(marker, arg)
  if arg == "" then
    return ""
  end
  local mapped = map_graphemes((arg:gsub("%s+", "")), marker == "^" and superscripts or subscripts)
  if mapped ~= nil and mapped ~= "" then
    return mapped
  end
  if #M.graphemes(arg) == 1 then
    return marker .. arg
  end
  return marker .. "(" .. arg .. ")"
end

local function with_combining(s, mark)
  local out = {}
  for _, g in ipairs(M.graphemes(s)) do
    out[#out + 1] = g:find("^%s$") and g or (g .. mark)
  end
  return table.concat(out)
end

local handlers = {}

-- Characters next to a fraction that keep `a/b` unambiguous without parentheses.
local FRACTION_BEFORE = "[=<>+%-,;:%(%[{|]$"
local FRACTION_AFTER = "^[=<>+%-,;:%)%]}|.]$"

local CLOSING_COMMANDS = { "right", "rangle", "rbrace", "rvert", "rVert", "}" }

local function bounded(text, before, after)
  local prefix = text:sub(1, before):gsub("%s+$", "")
  local left_ok = prefix == ""
    or (prefix:find(FRACTION_BEFORE) ~= nil and prefix:find("\\[,;:!>]$") == nil)
  local rest = text:sub(after):gsub("^%s+", "")
  local right_ok = rest == "" or rest:sub(1, 1):find(FRACTION_AFTER) ~= nil
  if not right_ok and rest:sub(1, 1) == "\\" then
    for _, name in ipairs(CLOSING_COMMANDS) do
      if rest:sub(2, #name + 1) == name then
        right_ok = true
      end
    end
  end
  return left_ok and right_ok
end

local function fraction(text, pos, start)
  local num, _, after_num = read_argument(text, pos)
  if num == nil then
    return nil
  end
  local den, _, after_den = read_argument(text, after_num)
  if den == nil then
    return nil
  end
  local vulgar = vulgar_fractions[num .. "/" .. den]
  if vulgar ~= nil then
    return vulgar, after_den
  end
  local result = wrap(num) .. "/" .. wrap(den)
  if not bounded(text, start - 1, after_den) then
    result = "(" .. result .. ")"
  end
  return result, after_den
end
handlers.frac = fraction
handlers.dfrac = fraction
handlers.tfrac = fraction
handlers.cfrac = fraction

local function binomial(text, pos)
  local n, _, after_n = read_argument(text, pos)
  if n == nil then
    return nil
  end
  local k, _, after_k = read_argument(text, after_n)
  if k == nil then
    return nil
  end
  return "C(" .. n .. "," .. k .. ")", after_k
end
handlers.binom = binomial
handlers.dbinom = binomial
handlers.tbinom = binomial

function handlers.sqrt(text, pos)
  local index, after_index = read_optional(text, pos)
  local arg, _, after = read_argument(text, after_index)
  if arg == nil then
    return nil
  end
  local roots = { ["2"] = "√", ["3"] = "∛", ["4"] = "∜" }
  local root = "√"
  if index ~= nil then
    index = convert(index)
    root = roots[index] or (script_text("^", index) .. "√")
  end
  return root .. wrap(arg), after
end

handlers["not"] = function(text, pos)
  local start = skip_spaces(text, pos)
  if start > #text then
    return nil
  end
  local piece, after = convert_token(text, start)
  return negations[piece] or (piece .. "\u{0338}"), after
end

local function stacked(above)
  return function(text, pos)
    local top, _, after_top = read_argument(text, pos)
    if top == nil then
      return nil
    end
    local base, _, after_base = read_argument(text, after_top)
    if base == nil then
      return nil
    end
    if above and base == "=" and stacked_equals[top] ~= nil then
      return stacked_equals[top], after_base
    end
    return base .. script_text(above and "^" or "_", top), after_base
  end
end
handlers.overset = stacked(true)
handlers.stackrel = stacked(true)
handlers.underset = stacked(false)

function handlers.pmod(text, pos)
  local arg, _, after = read_argument(text, pos)
  if arg == nil then
    return nil
  end
  return "(mod " .. arg .. ")", after
end

function handlers.color(text, pos)
  local arg, _, after = read_argument(text, pos)
  if arg == nil then
    return nil
  end
  return "", after
end

local function colored(text, pos)
  local color, _, after_color = read_argument(text, pos)
  if color == nil then
    return nil
  end
  local arg, _, after = read_argument(text, after_color)
  if arg == nil then
    return nil
  end
  return arg, after
end
handlers.textcolor = colored
handlers.colorbox = colored

local function boxed(text, pos)
  local arg, _, after = read_argument(text, pos)
  if arg == nil then
    return nil
  end
  return "[" .. arg .. "]", after
end
handlers.boxed = boxed
handlers.fbox = boxed

local function phantom(text, pos)
  local arg, _, after = read_argument(text, pos)
  if arg == nil then
    return nil
  end
  return (" "):rep(#M.graphemes(arg)), after
end
handlers.phantom = phantom
handlers.hphantom = phantom

function handlers.vphantom(text, pos)
  local arg, _, after = read_argument(text, pos)
  if arg == nil then
    return nil
  end
  return "", after
end

for name, mark in pairs(accents) do
  handlers[name] = function(text, pos)
    local arg, _, after = read_argument(text, pos)
    if arg == nil then
      return nil
    end
    return with_combining(arg, mark), after
  end
end

for name, font in pairs(fonts) do
  handlers[name] = function(text, pos)
    local arg, raw, after = read_argument(text, pos)
    if arg == nil then
      return nil
    end
    if font.text then
      arg = raw:gsub("\\([%%%$&#_{} ])", "%1"):gsub("~", " ")
    end
    if font.map ~= nil then
      arg = map_letters(arg, font.map)
    end
    return arg, after
  end
end

for name in pairs(sizing) do
  handlers[name] = function(text, pos)
    local start = skip_spaces(text, pos)
    if text:sub(start, start) == "." then
      return "", start + 1
    end
    return "", pos
  end
end

local function convert_command(text, pos)
  local _, name_end = text:find("^[A-Za-z]+", pos + 1)
  if name_end == nil then
    if pos + 1 > #text then
      return "\\", pos + 1
    end
    local _, char_end = text:find("^" .. CHAR, pos + 1)
    char_end = char_end or pos + 1
    local escaped = escapes[text:sub(pos + 1, char_end)]
    if escaped ~= nil then
      return escaped, char_end + 1
    end
    return text:sub(pos, char_end), char_end + 1
  end

  local name = text:sub(pos + 1, name_end)
  local next_pos = name_end + 1
  if name == "operatorname" and text:sub(next_pos, next_pos) == "*" then
    next_pos = next_pos + 1
  end

  local handler = handlers[name]
  if handler ~= nil then
    local piece, after = handler(text, next_pos, pos)
    if piece ~= nil then
      return piece, after
    end
    return text:sub(pos, next_pos - 1), next_pos
  end
  if symbols[name] ~= nil then
    return symbols[name], next_pos
  end
  if functions[name] then
    -- Keep `T\log T` from reading as `Tlog T`.
    if text:sub(pos - 1, pos - 1):find("^%w$") then
      return " " .. name, next_pos
    end
    return name, next_pos
  end

  -- Keep unknown commands and their braced arguments as written.
  local after = next_pos
  while text:sub(after, after) == "{" do
    local close = group_end(text, after)
    if close == nil then
      break
    end
    after = close + 1
  end
  return text:sub(pos, after - 1), after
end

convert_token = function(text, pos)
  local c = text:sub(pos, pos)
  if c == "\\" then
    return convert_command(text, pos)
  end
  if c == "{" then
    local close = group_end(text, pos)
    if close ~= nil then
      return convert(text:sub(pos + 1, close - 1)), close + 1
    end
    return c, pos + 1
  end
  if c == "^" or c == "_" then
    local arg, _, after = read_argument(text, pos + 1)
    if arg == nil then
      return c, pos + 1
    end
    return script_text(c, arg), after
  end
  if c == "'" then
    local _, run_end = text:find("^'+", pos)
    local count = run_end - pos + 1
    return primes[count] or primes[1]:rep(count), run_end + 1
  end
  if c == "~" then
    return " ", pos + 1
  end
  local _, char_end = text:find("^" .. CHAR, pos)
  char_end = char_end or pos
  return text:sub(pos, char_end), char_end + 1
end

---Converts inline LaTeX math to Unicode text.
---@param text string
---@return string
function M.convert(text)
  return convert(text)
end

-- Splits `text` into segments with source positions offset by `offset`. Groups and scripts that
-- cannot be written with Unicode script characters are split further, so the parts that can be
-- converted keep their own source ranges.
local function collect(text, offset, segments)
  local pos = 1
  while pos <= #text do
    local c = text:sub(pos, pos)
    local close = nil
    local marker_end = nil
    if c == "{" then
      close = group_end(text, pos)
      marker_end = pos - 1
    elseif c == "^" or c == "_" then
      local arg = read_argument(text, pos + 1)
      local arg_start = skip_spaces(text, pos + 1)
      if
        arg ~= nil
        and text:sub(arg_start, arg_start) == "{"
        and script_text(c, arg):sub(1, 1) == c
      then
        close = group_end(text, arg_start)
        marker_end = arg_start - 1
      end
    end

    if close ~= nil then
      local open = marker_end + 1
      local inner = text:sub(open + 1, close - 1)
      local multiple = c ~= "{" and #M.graphemes(convert(inner)) > 1
      if marker_end >= pos then
        segments[#segments + 1] = { offset + pos, offset + marker_end, c }
      end
      segments[#segments + 1] = { offset + open, offset + open, multiple and "(" or "" }
      collect(inner, offset + open, segments)
      segments[#segments + 1] = { offset + close, offset + close, multiple and ")" or "" }
      pos = close + 1
    else
      local piece, next_pos = convert_token(text, pos)
      segments[#segments + 1] = { offset + pos, offset + next_pos - 1, piece }
      pos = next_pos
    end
  end
end

local cache = {}
local cache_size = 0
local CACHE_LIMIT = 2000

---Replacements that render `text` as Unicode, for conceal marks.
---Columns are 1-based byte positions in `text`, inclusive. Each replacement has at most one
---character per source character; tokens whose Unicode form would be longer are left as written.
---@param text string
---@return { start_col: integer, end_col: integer, replacement: string }[]
function M.replacements(text)
  local cached = cache[text]
  if cached ~= nil then
    return cached
  end

  local segments = {}
  collect(text, 0, segments)
  local replacements = {}
  for _, segment in ipairs(segments) do
    local start_col, end_col, replacement = segment[1], segment[2], segment[3]
    local source = text:sub(start_col, end_col)
    if replacement ~= source and #M.graphemes(replacement) <= #M.char_starts(source) then
      replacements[#replacements + 1] = {
        start_col = start_col,
        end_col = end_col,
        replacement = replacement,
      }
    end
  end

  if cache_size >= CACHE_LIMIT then
    cache = {}
    cache_size = 0
  end
  cache[text] = replacements
  cache_size = cache_size + 1
  return replacements
end

return M
