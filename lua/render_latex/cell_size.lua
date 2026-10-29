local Config = require("render_latex.config")

local M = {}

local TIOCGWINSZ = {
  linux = 0x5413,
  mac = 0x40087468,
  bsd = 0x40087468,
}

local cached

local function ioctl_request()
  for feature, request in pairs(TIOCGWINSZ) do
    if vim.fn.has(feature) == 1 then
      return request
    end
  end
end

---Reads the terminal size in cells and pixels from the tty Neovim runs on.
---@return { cols: integer, rows: integer, xpixel: integer, ypixel: integer }|nil
function M.query()
  local request = ioctl_request()
  local ok_ffi, ffi = pcall(require, "ffi")
  if request == nil or not ok_ffi then
    return nil
  end
  -- Other plugins may already declare ioctl; a redeclaration error is harmless.
  pcall(ffi.cdef, "int ioctl(int fd, unsigned long request, ...);")
  pcall(
    ffi.cdef,
    "typedef struct { unsigned short row, col, xpixel, ypixel; } render_latex_winsize;"
  )
  -- An array argument reaches the vararg call as a pointer to its first element.
  local ok, buffer = pcall(ffi.new, "render_latex_winsize[1]")
  if not ok then
    return nil
  end
  local size = buffer[0]
  for _, fd in ipairs({ 1, 0, 2 }) do
    local called, result = pcall(ffi.C.ioctl, fd, request, buffer)
    if called and result == 0 and size.col > 0 and size.row > 0 then
      return { cols = size.col, rows = size.row, xpixel = size.xpixel, ypixel = size.ypixel }
    end
  end
  return nil
end

local function detect()
  local size = M.query()
  if size == nil or size.xpixel == 0 or size.ypixel == 0 then
    return { source = "fallback" }
  end
  return {
    source = "terminal",
    width = size.xpixel / size.cols,
    height = size.ypixel / size.rows,
  }
end

---Terminal cell size in pixels. Explicit `image.cell_width_px` and `image.cell_height_px`
---settings win; otherwise the size reported by the terminal is used, and the defaults are the
---fallback when the terminal reports no pixel size (Windows, remote UIs, some tmux setups).
---@return { width: number, height: number, source: 'config'|'terminal'|'fallback' }
function M.get()
  if cached == nil then
    cached = detect()
  end
  local width_explicit = Config.is_explicit("image.cell_width_px")
  local height_explicit = Config.is_explicit("image.cell_height_px")
  local source = cached.source
  if width_explicit and height_explicit then
    source = "config"
  end
  return {
    width = (width_explicit or cached.width == nil) and Config.image.cell_width_px or cached.width,
    height = (height_explicit or cached.height == nil) and Config.image.cell_height_px
      or cached.height,
    source = source,
  }
end

---Forgets the detected size, for example after the terminal font size changes.
function M.reset()
  cached = nil
end

return M
