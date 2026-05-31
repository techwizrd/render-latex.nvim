local Config = require("render_latex.config")
local Annotations = require("render_latex.annotations")
local Detect = require("render_latex.detect")
local ImageBackend = require("render_latex.image_backend")
local Sources = require("render_latex.sources")
local Util = require("render_latex.util")
local Viewport = require("render_latex.viewport")
local Worker = require("render_latex.worker")

local M = {}

local TEXT_SIZE_CALIBRATION = 0.85
local equations
local suppression = {
  cmdline = false,
  floating = false,
}
local last_backend_warning
local handle_focus_exit

local function should_skip_render_loop()
  return suppression.cmdline
end

local function should_hide_focused_equation(context, state, key)
  if context.hide_focused_equation then
    return true
  end
  if state.focus_revealed[key] then
    return true
  end
  local mode = vim.api.nvim_get_mode().mode
  return state.dirty[key] == true or mode:match("^[iR]") ~= nil
end

---@class render_latex.BufferState
---@field marks table<string, integer>
---@field images table<integer, table<string, integer>>
---@field metadata table<string, table>
---@field pending table<string, boolean>
---@field failures table<string, table>
---@field last_worker_error string?
---@field placements table<integer, table<string, string>>
---@field focused_keys table<integer, string>
---@field focus_revealed table<string, boolean>
---@field dirty table<string, boolean>
---@field equations table[]
---@field scanned boolean
---@field attached boolean
---@field inline_marks integer[]
---@field manual_raw table<string, boolean>
---@field exit_timers table<string, any>
---@field delayed_render table<string, boolean>
---@field placeholders table<string, integer>
---@field labels table<string, integer>
---@field source_line_marks table<string, integer[]>
---@field mark_layouts table<string, string>
---@field label_layouts table<string, string>
---@field viewports table<integer, { top: integer, bottom: integer, direction: 'up'|'down'|'still' }>
---@field source_dirty boolean
---@field source_revision string?
---@field scroll_scheduled boolean
---@field worker_retries integer
---@field worker_retry_scheduled boolean
---@field timer any

---@type table<integer, render_latex.BufferState>
local buffers = {}

ImageBackend.on_change(function(status)
  last_backend_warning = nil
  if status ~= "supported" then
    return
  end

  for bufnr, state in pairs(buffers) do
    if state.attached and Util.buf_is_valid(bufnr) then
      M.queue(bufnr)
    end
  end
end)

local function get_buffer_state(bufnr)
  local state = buffers[bufnr]
  if state ~= nil then
    return state
  end

  state = {
    marks = {},
    images = {},
    metadata = {},
    pending = {},
    failures = {},
    last_worker_error = nil,
    placements = {},
    focused_keys = {},
    focus_revealed = {},
    dirty = {},
    equations = {},
    scanned = false,
    attached = false,
    inline_marks = {},
    manual_raw = {},
    exit_timers = {},
    delayed_render = {},
    placeholders = {},
    labels = {},
    source_line_marks = {},
    mark_layouts = {},
    label_layouts = {},
    viewports = {},
    source_dirty = false,
    source_revision = nil,
    scroll_scheduled = false,
    worker_retries = 0,
    worker_retry_scheduled = false,
    timer = nil,
  }
  buffers[bufnr] = state
  return state
end

local blob_cache = {
  order = {},
  values = {},
  limit = 64,
}

local function blob_cache_get(cache_key)
  return blob_cache.values[cache_key]
end

local function blob_cache_put(cache_key, blob)
  if blob_cache.values[cache_key] == nil then
    blob_cache.order[#blob_cache.order + 1] = cache_key
  end
  blob_cache.values[cache_key] = blob

  while #blob_cache.order > blob_cache.limit do
    local oldest = table.remove(blob_cache.order, 1)
    blob_cache.values[oldest] = nil
  end
end

local function resolve_foreground(equation)
  if Config.render.foreground ~= nil then
    return Config.render.foreground, "render.foreground"
  end

  if Config.render.match_text_color then
    if equation ~= nil and equation.quoted then
      local quote_hex, quote_source =
        Util.get_first_hl_hex({ "@markup.quote", "markdownBlockquote", "Comment" })
      if quote_hex ~= nil then
        return quote_hex, quote_source
      end
    end

    local hex, source = Util.get_first_hl_hex({ "@markup.math", "Normal" })
    if hex ~= nil then
      return hex, source
    end
  end

  return Util.get_hl_hex("Normal") or "#ffffff", "fallback"
end

local function resolve_font_size()
  local preset_scale = {
    match_text = 1.0,
    compact = 0.9,
    presentation = 1.25,
  }

  if not Config.render.match_text_size then
    return Config.render.font_size
  end

  local base = Config.image.cell_height_px * TEXT_SIZE_CALIBRATION
  return math.max(1, base * (preset_scale[Config.render.preset] or 1.0) * Config.render.text_scale)
end

local function resolved_render_options(equation)
  local foreground, source = resolve_foreground(equation)
  return {
    foreground = foreground,
    foreground_source = source,
    font_size = resolve_font_size(),
    scale = Config.render.scale,
    background = Config.render.background,
    padding = Config.render.padding,
    cell_width_px = Config.image.cell_width_px,
    cell_height_px = Config.image.cell_height_px,
  }
end

local function cached_render_options(cache, equation)
  local key = equation ~= nil and equation.quoted and "quoted" or "default"
  if cache[key] == nil then
    cache[key] = resolved_render_options(equation)
  end
  return cache[key]
end

local function render_fingerprint(opts)
  return table.concat({
    opts.foreground,
    opts.background,
    opts.font_size,
    opts.padding,
    opts.scale,
    opts.cell_width_px,
    opts.cell_height_px,
  }, ":")
end

local function render_payload(equation, opts)
  return {
    formula = equation.text,
    display_mode = true,
    foreground_color = opts.foreground,
    background = opts.background,
    font_size = opts.font_size,
    padding = opts.padding,
    scale = opts.scale,
    theme_fingerprint = table.concat(
      { opts.foreground_source, opts.foreground, opts.font_size },
      ":"
    ),
  }
end

local with_backend_batch

local function clear_images(bufnr)
  local state = buffers[bufnr]
  if state == nil then
    return
  end

  local backend = ImageBackend.get()
  if backend == nil then
    state.images = {}
    state.placements = {}
    return
  end

  with_backend_batch(backend, function()
    for _, image_ids in pairs(state.images) do
      for _, image_id in pairs(image_ids) do
        pcall(backend.del, image_id)
      end
    end
  end)
  state.images = {}
  state.placements = {}
end

local function only_focused_window(state, winid, key)
  for other_winid, other_key in pairs(state.focused_keys) do
    if other_winid ~= winid and other_key == key then
      return false
    end
  end
  return true
end

local function clear_window_images(bufnr, state, winid)
  local focused_key = state.focused_keys[winid]
  if focused_key ~= nil and only_focused_window(state, winid, focused_key) then
    handle_focus_exit(bufnr, state, focused_key, equations(bufnr), false)
  end

  local image_ids = state.images[winid]
  if image_ids ~= nil then
    local backend = ImageBackend.get()
    if backend ~= nil then
      with_backend_batch(backend, function()
        for _, image_id in pairs(image_ids) do
          pcall(backend.del, image_id)
        end
      end)
    end
  end
  state.images[winid] = nil
  state.placements[winid] = nil
  state.focused_keys[winid] = nil
  state.viewports[winid] = nil
end

local function clear_marks(bufnr)
  local state = buffers[bufnr]
  if state == nil then
    return
  end
  Annotations.clear_marks(bufnr, Config.ns, state)
  for _, mark_ids in pairs(state.source_line_marks) do
    for _, mark_id in ipairs(mark_ids) do
      pcall(vim.api.nvim_buf_del_extmark, bufnr, Config.ns, mark_id)
    end
  end
  state.source_line_marks = {}
  state.mark_layouts = {}
  state.label_layouts = {}
end

local function clear_source_line_marks(bufnr, state, key)
  for _, mark_id in ipairs(state.source_line_marks[key] or {}) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, Config.ns, mark_id)
  end
  state.source_line_marks[key] = nil
end

local function clear_equation_display(bufnr, key, backend, backend_resolved)
  local state = buffers[bufnr]
  if state == nil then
    return
  end

  local mark_id = state.marks[key]
  if mark_id ~= nil then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, Config.ns, mark_id)
    state.marks[key] = nil
  end
  clear_source_line_marks(bufnr, state, key)
  state.mark_layouts[key] = nil
  Annotations.clear_placeholder(bufnr, Config.ns, state, key)
  Annotations.clear_label(bufnr, Config.ns, state, key)

  if not backend_resolved then
    backend = ImageBackend.get()
  end
  with_backend_batch(backend, function()
    for winid, image_ids in pairs(state.images) do
      local image_id = image_ids[key]
      if image_id ~= nil then
        if backend ~= nil then
          pcall(backend.del, image_id)
        end
        image_ids[key] = nil
      end
      if state.placements[winid] ~= nil then
        state.placements[winid][key] = nil
      end
    end
  end)
end

local function cancel_delayed_render(state, key)
  local timer = state.exit_timers[key]
  if timer ~= nil then
    timer:stop()
    timer:close()
    state.exit_timers[key] = nil
  end
  state.delayed_render[key] = nil
end

local function equation_content_hash(equation)
  return Util.sha256(equation.text)
end

local function schedule_delayed_render(bufnr, key)
  local state = get_buffer_state(bufnr)
  cancel_delayed_render(state, key)

  local timer = vim.uv.new_timer()
  state.exit_timers[key] = timer
  state.delayed_render[key] = true
  local indexed = equations(bufnr)
  for _, equation in ipairs(indexed) do
    if equation.key == key then
      Annotations.set_placeholder(bufnr, Config.ns, state, equation)
      break
    end
  end
  timer:start(Config.render.exit_delay_ms, 0, function()
    vim.schedule(function()
      local current = buffers[bufnr]
      if current == nil then
        return
      end
      cancel_delayed_render(current, key)
      Annotations.clear_placeholder(bufnr, Config.ns, current, key)
      M.queue(bufnr)
    end)
  end)
end

handle_focus_exit = function(bufnr, state, key, indexed_equations, schedule)
  clear_equation_display(bufnr, key)
  state.focus_revealed[key] = nil
  if not state.dirty[key] then
    return
  end

  local previous_equation = nil
  for _, equation in ipairs(indexed_equations or {}) do
    if equation.key == key then
      previous_equation = equation
      break
    end
  end

  local meta = state.metadata[key]
  local next_hash = previous_equation and equation_content_hash(previous_equation) or nil
  if meta == nil or next_hash == nil or meta.content_hash ~= next_hash then
    state.metadata[key] = nil
    if schedule then
      schedule_delayed_render(bufnr, key)
    end
  end
  state.dirty[key] = nil
end

equations = function(bufnr)
  local state = get_buffer_state(bufnr)
  if not Sources.incremental(bufnr) then
    local revision = Sources.revision(bufnr)
    if state.source_dirty or not state.scanned or revision ~= state.source_revision then
      state.equations = Sources.display_equations(bufnr)
      state.source_dirty = false
      state.source_revision = revision
      state.scanned = true
    end
    return state.equations
  end
  if not state.scanned then
    state.equations = Sources.display_equations(bufnr)
    state.scanned = true
  end
  return state.equations
end

local function visible_inline_ranges(bufnr)
  local ranges = {}
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if Util.win_is_valid(winid) then
      local top = math.max(0, vim.fn.line("w0", winid) - 1)
      local bottom = math.min(line_count - 1, vim.fn.line("w$", winid) - 1)
      ranges[#ranges + 1] = { start_row = top, end_row = bottom }
    end
  end
  if #ranges == 0 then
    return nil
  end
  return Sources.inline_ranges(bufnr, ranges)
end

local function failure_matches(failure, content_hash, render_fingerprint)
  return failure ~= nil
    and failure.content_hash == content_hash
    and failure.render_fingerprint == render_fingerprint
end

local function metadata_matches(meta, equation, option_cache)
  return meta ~= nil
    and meta.content_hash == equation_content_hash(equation)
    and meta.render_fingerprint
      == render_fingerprint(cached_render_options(option_cache, equation))
end

local function record_render_failure(state, equation, content_hash, render_fingerprint, message)
  state.failures[equation.key] = {
    content_hash = content_hash,
    render_fingerprint = render_fingerprint,
    message = message,
  }
  Util.warn(("Failed to render equation: %s"):format(message))
end

local function retryable_worker_error(err)
  return err == "worker request timed out"
    or err == "worker exited"
    or err:match("^worker exited:") ~= nil
end

local function schedule_worker_retry(bufnr, state)
  if state.worker_retry_scheduled or state.worker_retries >= 2 then
    return
  end
  state.worker_retries = state.worker_retries + 1
  state.worker_retry_scheduled = true
  vim.defer_fn(function()
    vim.schedule(function()
      local current = buffers[bufnr]
      if current == nil then
        return
      end
      current.worker_retry_scheduled = false
      M.queue(bufnr)
    end)
  end, 500 * state.worker_retries)
end

local function prune_stale_state(state, indexed_equations)
  local active = {}
  for _, equation in ipairs(indexed_equations) do
    active[equation.key] = true
  end

  for _, map in ipairs({
    state.metadata,
    state.failures,
    state.manual_raw,
    state.focus_revealed,
    state.dirty,
    state.mark_layouts,
    state.label_layouts,
  }) do
    for key, _ in pairs(map) do
      if not active[key] then
        map[key] = nil
      end
    end
  end

  for key, _ in pairs(state.delayed_render) do
    if not active[key] then
      cancel_delayed_render(state, key)
    end
  end
end

local function release_focused_equations(bufnr, state)
  local indexed_equations = equations(bufnr)
  local seen = {}
  for _, key in pairs(state.focused_keys) do
    if not seen[key] then
      seen[key] = true
      handle_focus_exit(bufnr, state, key, indexed_equations, false)
    end
  end
end

function M.clear(bufnr)
  clear_images(bufnr)
  clear_marks(bufnr)
  local state = buffers[bufnr]
  if state ~= nil then
    release_focused_equations(bufnr, state)
    state.focused_keys = {}
    state.focus_revealed = {}
    state.dirty = {}
    state.equations = {}
    state.scanned = false
    state.failures = {}
    state.manual_raw = {}
    state.viewports = {}
    state.source_dirty = false
    state.source_revision = nil
    state.scroll_scheduled = false
    for key, _ in pairs(state.exit_timers) do
      cancel_delayed_render(state, key)
    end
  end
end

function M.clear_all()
  local backend = ImageBackend.get()
  if backend ~= nil then
    pcall(backend.del, math.huge)
  end

  for bufnr, state in pairs(buffers) do
    clear_marks(bufnr)
    if state.timer ~= nil then
      state.timer:stop()
    end
    state.images = {}
    state.placements = {}
    release_focused_equations(bufnr, state)
    state.focused_keys = {}
    state.focus_revealed = {}
    state.dirty = {}
    state.equations = {}
    state.scanned = false
    state.failures = {}
    state.manual_raw = {}
    state.viewports = {}
    state.source_dirty = false
    state.source_revision = nil
    state.scroll_scheduled = false
    for key, _ in pairs(state.exit_timers) do
      cancel_delayed_render(state, key)
    end
  end
end

function M.hide_all()
  local backend = ImageBackend.get()
  if backend ~= nil then
    pcall(backend.del, math.huge)
  end

  for bufnr, state in pairs(buffers) do
    clear_marks(bufnr)
    if state.timer ~= nil then
      state.timer:stop()
    end
    state.images = {}
    state.placements = {}
    state.scroll_scheduled = false
  end
end

local function hide_visible()
  local backend = ImageBackend.get()
  if backend ~= nil then
    pcall(backend.del, math.huge)
  end

  for _, state in pairs(buffers) do
    state.images = {}
    state.placements = {}
  end
end

local function find_equation_at_row(equations, row)
  for _, equation in ipairs(equations) do
    if row >= equation.start_row and row <= equation.end_row then
      return equation
    end
  end
  return nil
end

local function active_focus_counts(focused_keys)
  local active = {}
  for _, key in pairs(focused_keys) do
    active[key] = (active[key] or 0) + 1
  end
  return active
end

local function sync_focus(bufnr, indexed_equations, snapshot)
  local state = get_buffer_state(bufnr)
  local next_focused_keys = {}
  for _, winid in ipairs(snapshot.winids) do
    local focused = find_equation_at_row(indexed_equations, snapshot.windows[winid].cursor_row)
    if focused ~= nil then
      next_focused_keys[winid] = focused.key
    end
  end

  local previous_active = active_focus_counts(state.focused_keys)
  local next_active = active_focus_counts(next_focused_keys)

  for key, _ in pairs(previous_active) do
    if next_active[key] == nil then
      handle_focus_exit(bufnr, state, key, indexed_equations, true)
    end
  end

  for key, _ in pairs(next_active) do
    if previous_active[key] == nil then
      cancel_delayed_render(state, key)
      if state.metadata[key] ~= nil or state.marks[key] ~= nil then
        state.focus_revealed[key] = true
      end
      clear_equation_display(bufnr, key)
    end
  end

  state.focused_keys = next_focused_keys

  local focused = {}
  for key, _ in pairs(next_active) do
    focused[key] = true
  end
  return focused
end

local function ensure_mark(bufnr, equation, meta, context)
  local state = get_buffer_state(bufnr)
  local source_lines = equation.end_row - equation.start_row + 1
  local reserved = math.max(0, meta.height_cells - source_lines)
  local layout = table.concat({
    equation.start_row,
    equation.end_row,
    reserved,
    Config.conceal and 1 or 0,
    context.clear_source_line_background and 1 or 0,
  }, ":")
  if state.marks[equation.key] ~= nil and state.mark_layouts[equation.key] == layout then
    return
  end
  local virt_lines = {}

  for _ = 1, reserved do
    virt_lines[#virt_lines + 1] = { { " ", "Conceal" } }
  end

  if state.marks[equation.key] ~= nil then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, Config.ns, state.marks[equation.key])
  end
  for _, mark_id in ipairs(state.source_line_marks[equation.key] or {}) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, Config.ns, mark_id)
  end
  state.source_line_marks[equation.key] = {}

  state.marks[equation.key] =
    vim.api.nvim_buf_set_extmark(bufnr, Config.ns, equation.start_row, 0, {
      end_row = equation.end_row + 1,
      end_col = 0,
      virt_lines = virt_lines,
      conceal = Config.conceal and "" or nil,
      hl_mode = "combine",
      priority = 250,
    })
  if context.clear_source_line_background then
    for row = equation.start_row, equation.end_row do
      state.source_line_marks[equation.key][#state.source_line_marks[equation.key] + 1] =
        vim.api.nvim_buf_set_extmark(bufnr, Config.ns, row, 0, {
          line_hl_group = "Normal",
          priority = 255,
        })
    end
  end
  state.mark_layouts[equation.key] = layout
end

local function collect_window_snapshot(bufnr, viewport_state, prefetch)
  local snapshot = {
    winids = {},
    ranges = {},
    windows = {},
  }

  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if Util.win_is_valid(winid) then
      local top, bottom = Viewport.viewport_range(viewport_state, winid, prefetch)
      local text_top, text_bottom = Viewport.visible_text_bounds(winid)
      snapshot.winids[#snapshot.winids + 1] = winid
      snapshot.ranges[#snapshot.ranges + 1] = { top = top, bottom = bottom }
      snapshot.windows[winid] = {
        width = vim.api.nvim_win_get_width(winid),
        text_top = text_top,
        text_bottom = text_bottom,
        cursor_row = vim.api.nvim_win_get_cursor(winid)[1] - 1,
      }
    end
  end

  return snapshot
end

with_backend_batch = function(backend, callback)
  local has_batch = backend ~= nil
    and type(backend.begin_batch) == "function"
    and type(backend.flush_batch) == "function"
  if has_batch then
    backend.begin_batch()
  end

  local ok, result = pcall(callback)

  if has_batch then
    backend.flush_batch()
  end

  if not ok then
    error(result)
  end

  return result
end

local function visible_equations_from_ranges(indexed_equations, ranges)
  local visible = {}
  for _, equation in ipairs(indexed_equations) do
    if not Viewport.fold_closed(equation) then
      for _, range in ipairs(ranges) do
        if equation.end_row >= range.top and equation.start_row <= range.bottom then
          visible[#visible + 1] = equation
          break
        end
      end
    end
  end
  return visible
end

local function should_suppress_label(context)
  return context.suppress_default_equation_labels
    and not Config.is_explicit("render.equation_labels")
end

local function clear_suppressed_label(context, bufnr, state, equation)
  if should_suppress_label(context) then
    Annotations.clear_label(bufnr, Config.ns, state, equation.key)
  end
end

local function update_label(context, bufnr, state, equation, visible_index)
  if should_suppress_label(context) then
    Annotations.clear_label(bufnr, Config.ns, state, equation.key)
    return
  end
  Annotations.set_equation_label(bufnr, Config.ns, state, equation, visible_index)
end

local function update_image(bufnr, winid, equation, meta, backend, window)
  if not Util.win_is_valid(winid) then
    return false
  end

  local position = vim.fn.screenpos(winid, equation.start_row + 1, 1)
  if type(position) ~= "table" or position.row == 0 then
    return false
  end

  local text_top = window.text_top
  local text_bottom = window.text_bottom
  if text_top == nil then
    return false
  end

  local row = math.max(position.row, text_top)
  local max_height = text_bottom - row + 1
  if max_height <= 0 or meta.height_cells > max_height then
    return false
  end

  local state = get_buffer_state(bufnr)
  state.images[winid] = state.images[winid] or {}
  state.placements[winid] = state.placements[winid] or {}

  local bounds = Sources.image_bounds(bufnr, winid, window, position)
  local width = math.max(1, bounds.width or window.width)
  local start_col = bounds.start_col or position.col
  local col = start_col + math.max(0, math.floor((width - meta.width_cells) / 2))
  local opts = {
    row = row,
    col = col,
    width = meta.width_cells,
    height = meta.height_cells,
    zindex = Config.image.zindex,
  }
  local placement_fingerprint = table.concat({ opts.row, opts.col, opts.width, opts.height }, ":")
  if backend == nil then
    local _, _, reason = ImageBackend.get()
    if last_backend_warning ~= reason then
      last_backend_warning = reason
      Util.warn(reason or "No image backend is available")
    end
    return false
  end
  last_backend_warning = nil

  local image_id = state.images[winid][equation.key]
  if image_id == nil then
    local blob = blob_cache_get(meta.cache_key)
    if blob == nil then
      local ok, result = pcall(vim.fn.readblob, meta.png_path)
      if not ok then
        state.metadata[equation.key] = nil
        Util.warn(("Failed to read rendered equation image: %s"):format(result))
        return false
      end
      blob = result
      blob_cache_put(meta.cache_key, blob)
    end

    local ok, result = pcall(backend.set, blob, opts)
    if not ok then
      Util.warn(("Failed to place rendered equation image: %s"):format(result))
      return false
    end
    state.images[winid][equation.key] = result
    state.placements[winid][equation.key] = placement_fingerprint
  else
    if state.placements[winid][equation.key] ~= placement_fingerprint then
      local ok, result = pcall(backend.set, image_id, opts)
      if not ok then
        Util.warn(("Failed to update rendered equation image: %s"):format(result))
        pcall(backend.del, image_id)
        state.images[winid][equation.key] = nil
        state.placements[winid][equation.key] = nil
        return false
      end
      state.placements[winid][equation.key] = placement_fingerprint
    end
  end

  return true
end

local function cleanup_inactive(state, bufnr, active, active_images, backend)
  for key, mark_id in pairs(state.marks) do
    if not active[key] then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, Config.ns, mark_id)
      state.marks[key] = nil
      state.mark_layouts[key] = nil
      clear_source_line_marks(bufnr, state, key)
    end
  end

  for key, mark_id in pairs(state.labels) do
    if not active[key] then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, Config.ns, mark_id)
      state.labels[key] = nil
      state.label_layouts[key] = nil
    end
  end

  for winid, image_ids in pairs(state.images) do
    if not Util.win_is_valid(winid) then
      clear_window_images(bufnr, state, winid)
    else
      local keep = active_images[winid] or {}
      for key, image_id in pairs(image_ids) do
        if not keep[key] then
          if backend ~= nil then
            pcall(backend.del, image_id)
          end
          image_ids[key] = nil
          state.placements[winid][key] = nil
        end
      end
    end
  end
end

local function update_existing_visible(bufnr, indexed_equations, snapshot)
  local state = get_buffer_state(bufnr)
  local active = {}
  local active_images = {}
  local visible_index = 0
  local option_cache = {}
  local backend_status = ImageBackend.status()
  local backend = backend_status.available and ImageBackend.get() or nil
  local floating_suppressed = suppression.floating
  local needs_render = false
  local focused = active_focus_counts(state.focused_keys)
  local context = Sources.render_context(bufnr)

  with_backend_batch(backend, function()
    for _, equation in ipairs(visible_equations_from_ranges(indexed_equations, snapshot.ranges)) do
      visible_index = visible_index + 1
      active[equation.key] = true
      clear_suppressed_label(context, bufnr, state, equation)
      local meta = state.metadata[equation.key]
      if focused[equation.key] and should_hide_focused_equation(context, state, equation.key) then
        clear_equation_display(bufnr, equation.key, backend, true)
      elseif state.manual_raw[equation.key] or state.delayed_render[equation.key] then
        clear_equation_display(bufnr, equation.key, backend, true)
      elseif floating_suppressed then
        clear_equation_display(bufnr, equation.key, backend, true)
        if not metadata_matches(meta, equation, option_cache) then
          needs_render = true
        end
      elseif not metadata_matches(meta, equation, option_cache) then
        needs_render = true
      elseif backend == nil then
        clear_equation_display(bufnr, equation.key, backend, true)
        if last_backend_warning ~= backend_status.reason then
          last_backend_warning = backend_status.reason
          Util.warn(backend_status.reason or "No image backend is available")
        end
        needs_render = true
      else
        ensure_mark(bufnr, equation, meta, context)
        update_label(context, bufnr, state, equation, visible_index)
        for _, winid in ipairs(snapshot.winids) do
          if update_image(bufnr, winid, equation, meta, backend, snapshot.windows[winid]) then
            active_images[winid] = active_images[winid] or {}
            active_images[winid][equation.key] = true
          end
        end
      end
    end
    cleanup_inactive(state, bufnr, active, active_images, backend)
  end)
  return needs_render
end

local function request_renders(bufnr, equations_to_render)
  if #equations_to_render == 0 then
    return
  end

  local state = get_buffer_state(bufnr)
  local items = {}
  local pending_equations = {}
  local content_hashes = {}
  local render_fingerprints = {}
  local option_cache = {}

  for _, equation in ipairs(equations_to_render) do
    if not state.pending[equation.key] then
      local opts = cached_render_options(option_cache, equation)
      local fingerprint = render_fingerprint(opts)
      local content_hash = equation_content_hash(equation)
      local existing = state.metadata[equation.key]
      local unchanged = existing ~= nil
        and existing.render_fingerprint == fingerprint
        and existing.content_hash == content_hash

      if
        not unchanged
        and not failure_matches(state.failures[equation.key], content_hash, fingerprint)
      then
        state.pending[equation.key] = true
        pending_equations[#pending_equations + 1] = equation
        content_hashes[equation.key] = content_hash
        render_fingerprints[equation.key] = fingerprint
        items[#items + 1] = render_payload(equation, opts)
      end
    end
  end

  if #items == 0 then
    return
  end

  Worker.request_batch(items, function(results, err)
    if err ~= nil then
      for _, equation in ipairs(pending_equations) do
        state.pending[equation.key] = nil
      end
      if err == "worker installing" or err == "worker building" then
        return
      end
      if state.last_worker_error ~= err then
        state.last_worker_error = err
        Util.warn(("Failed to render equations: %s"):format(err))
      end
      if retryable_worker_error(err) then
        schedule_worker_retry(bufnr, state)
      end
      return
    end
    state.last_worker_error = nil
    state.worker_retries = 0
    state.worker_retry_scheduled = false

    local needs_rerender = false
    for index, equation in ipairs(pending_equations) do
      state.pending[equation.key] = nil
      local item = results[index]
      if item ~= nil and item.error == nil and item.result ~= nil then
        item.result.width_cells = Util.round_up(item.result.width_px / Config.image.cell_width_px)
        item.result.height_cells =
          Util.round_up(item.result.height_px / Config.image.cell_height_px)
        item.result.render_fingerprint = render_fingerprints[equation.key]
        item.result.content_hash = content_hashes[equation.key]
        state.metadata[equation.key] = item.result
        state.failures[equation.key] = nil
        needs_rerender = true
      else
        local message = item and item.error and item.error.message or "unknown worker error"
        record_render_failure(
          state,
          equation,
          content_hashes[equation.key],
          render_fingerprints[equation.key],
          message
        )
      end
    end

    if needs_rerender then
      vim.schedule(function()
        M.render(bufnr)
      end)
    end
  end)
end

---@param bufnr integer
function M.render(bufnr)
  if not Util.buf_is_valid(bufnr) then
    return
  end
  if should_skip_render_loop() then
    M.hide_all()
    return
  end
  local limits = Viewport.render_limits(vim.api.nvim_buf_line_count(bufnr))
  if not Config.enabled or not Sources.supports(bufnr) then
    M.clear(bufnr)
    return
  end
  if limits.disabled then
    M.clear(bufnr)
    return
  end
  if not Config.should_render_mode(vim.api.nvim_get_mode().mode) then
    return
  end

  local state = get_buffer_state(bufnr)
  local indexed_equations = equations(bufnr)
  prune_stale_state(state, indexed_equations)
  Annotations.render_inline_fallback(bufnr, Config.ns, state, visible_inline_ranges(bufnr))
  local snapshot = collect_window_snapshot(bufnr, state.viewports, limits.prefetch)
  local focused_keys = sync_focus(bufnr, indexed_equations, snapshot)
  local active = {}
  local active_images = {}
  local backend_status = ImageBackend.status()
  local backend = backend_status.available and ImageBackend.get() or nil
  local floating_suppressed = suppression.floating
  local batch = {}
  local visible_index = 0
  local option_cache = {}
  local context = Sources.render_context(bufnr)

  with_backend_batch(backend, function()
    for _, equation in ipairs(visible_equations_from_ranges(indexed_equations, snapshot.ranges)) do
      visible_index = visible_index + 1
      active[equation.key] = true
      clear_suppressed_label(context, bufnr, state, equation)
      local meta = state.metadata[equation.key]
      if
        focused_keys[equation.key] and should_hide_focused_equation(context, state, equation.key)
      then
        clear_equation_display(bufnr, equation.key, backend, true)
      elseif state.manual_raw[equation.key] then
        clear_equation_display(bufnr, equation.key, backend, true)
      elseif state.delayed_render[equation.key] then
        clear_equation_display(bufnr, equation.key, backend, true)
      elseif floating_suppressed then
        clear_equation_display(bufnr, equation.key, backend, true)
        if not metadata_matches(meta, equation, option_cache) then
          batch[#batch + 1] = equation
        end
      elseif not backend_status.available then
        clear_equation_display(bufnr, equation.key, backend, true)
        if last_backend_warning ~= backend_status.reason then
          last_backend_warning = backend_status.reason
          Util.warn(backend_status.reason or "No image backend is available")
        end
      elseif not metadata_matches(meta, equation, option_cache) then
        batch[#batch + 1] = equation
      else
        ensure_mark(bufnr, equation, meta, context)
        update_label(context, bufnr, state, equation, visible_index)
        for _, winid in ipairs(snapshot.winids) do
          if update_image(bufnr, winid, equation, meta, backend, snapshot.windows[winid]) then
            active_images[winid] = active_images[winid] or {}
            active_images[winid][equation.key] = true
          end
        end
      end
    end
    cleanup_inactive(state, bufnr, active, active_images, backend)
  end)

  request_renders(bufnr, batch)
end

---@param bufnr integer
function M.refresh_visible(bufnr)
  if not Util.buf_is_valid(bufnr) then
    return
  end
  if should_skip_render_loop() then
    return
  end

  local limits = Viewport.render_limits(vim.api.nvim_buf_line_count(bufnr))
  if not Config.enabled or not Sources.supports(bufnr) or limits.disabled then
    return
  end
  if not Config.should_render_mode(vim.api.nvim_get_mode().mode) then
    return
  end

  local state = get_buffer_state(bufnr)
  local indexed_equations = equations(bufnr)
  prune_stale_state(state, indexed_equations)
  local snapshot = collect_window_snapshot(bufnr, state.viewports, limits.prefetch)
  if #snapshot.winids == 0 then
    return
  end

  if update_existing_visible(bufnr, indexed_equations, snapshot) then
    M.queue(bufnr)
  end
end

---@param bufnr integer
function M.scroll(bufnr)
  if not Util.buf_is_valid(bufnr) then
    return
  end

  local state = get_buffer_state(bufnr)
  if state.scroll_scheduled then
    return
  end

  state.scroll_scheduled = true
  vim.schedule(function()
    local current = buffers[bufnr]
    if current == nil then
      return
    end
    current.scroll_scheduled = false
    M.refresh_visible(bufnr)
  end)
end

---@param bufnr integer
function M.queue(bufnr)
  if not Util.buf_is_valid(bufnr) then
    return
  end

  local state = get_buffer_state(bufnr)
  if state.timer == nil then
    state.timer = vim.uv.new_timer()
  else
    state.timer:stop()
  end

  state.timer:start(Config.debounce, 0, function()
    vim.schedule(function()
      M.render(bufnr)
    end)
  end)
end

---@param bufnr integer
function M.attach(bufnr)
  local state = get_buffer_state(bufnr)
  if state.attached or not Util.buf_is_valid(bufnr) then
    return
  end

  state.equations = Sources.display_equations(bufnr)
  state.scanned = true
  state.source_dirty = false
  state.source_revision = Sources.revision(bufnr)
  state.attached = true

  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, buffer, _, firstline, lastline, new_lastline)
      local current = buffers[buffer]
      if current == nil then
        return true
      end
      if Sources.incremental(buffer) then
        current.equations =
          Detect.update(current.equations, buffer, firstline, lastline - 1, new_lastline - 1)
        current.scanned = true
      else
        current.source_dirty = true
        current.scanned = false
      end
    end,
    on_detach = function(_, buffer)
      local current = buffers[buffer]
      if current ~= nil then
        current.attached = false
      end
    end,
  })
end

---@param bufnr integer
---@param queue_render boolean?
function M.on_text_changed(bufnr, queue_render)
  local state = buffers[bufnr]
  if state ~= nil then
    for _, key in pairs(state.focused_keys) do
      state.dirty[key] = true
    end
  end
  if queue_render ~= false then
    M.queue(bufnr)
  end
end

---@param bufnr integer
---@param winid integer
function M.detach_window(bufnr, winid)
  local state = buffers[bufnr]
  if state == nil then
    return
  end
  clear_window_images(bufnr, state, winid)
end

---@param winid integer
function M.detach_winid(winid)
  for bufnr, state in pairs(buffers) do
    clear_window_images(bufnr, state, winid)
  end
end

function M.current_equation(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local winid = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(winid) ~= bufnr then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(winid)[1] - 1
  for _, equation in ipairs(equations(bufnr)) do
    if row >= equation.start_row and row <= equation.end_row then
      return equation
    end
  end
  return nil
end

function M.current_equation_source(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local equation = M.current_equation(bufnr)
  if equation == nil then
    return nil, "cursor is not inside a display equation"
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, equation.start_row, equation.end_row + 1, false)
  return {
    equation = equation,
    lines = lines,
    text = table.concat(lines, "\n"),
  },
    nil
end

function M.rerender_current(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local equation = M.current_equation(bufnr)
  if equation == nil then
    return false, "cursor is not inside a display equation"
  end

  local state = get_buffer_state(bufnr)
  cancel_delayed_render(state, equation.key)
  state.metadata[equation.key] = nil
  state.failures[equation.key] = nil
  state.manual_raw[equation.key] = nil
  M.queue(bufnr)
  return true, equation
end

function M.toggle_current(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local equation = M.current_equation(bufnr)
  if equation == nil then
    return false, "cursor is not inside a display equation"
  end

  local state = get_buffer_state(bufnr)
  local next_value = not state.manual_raw[equation.key]
  state.manual_raw[equation.key] = next_value
  cancel_delayed_render(state, equation.key)
  clear_equation_display(bufnr, equation.key)
  M.queue(bufnr)
  return true, next_value
end

function M.debug_current(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local equation = M.current_equation(bufnr)
  if equation == nil then
    return nil, "cursor is not inside a display equation"
  end

  local state = get_buffer_state(bufnr)
  local focused = active_focus_counts(state.focused_keys)
  return {
    equation = equation,
    focused = focused[equation.key] ~= nil,
    dirty = state.dirty[equation.key] == true,
    manual_raw = state.manual_raw[equation.key] == true,
    delayed_render = state.delayed_render[equation.key] == true,
    metadata = state.metadata[equation.key],
  },
    nil
end

function M.resolved_options(equation)
  return resolved_render_options(equation)
end

---@param reason 'cmdline'|'floating'
---@param value boolean
function M.set_suppressed(reason, value)
  if suppression[reason] == value then
    return
  end
  suppression[reason] = value
  if suppression.cmdline then
    M.hide_all()
  elseif suppression.floating then
    hide_visible()
  end
end

function M.suppression_status()
  return vim.deepcopy(suppression)
end

---@param bufnr integer
function M.detach(bufnr)
  local state = buffers[bufnr]
  if state == nil then
    return
  end
  M.clear(bufnr)
  if state.timer ~= nil then
    state.timer:stop()
    state.timer:close()
  end
  buffers[bufnr] = nil
end

return M
