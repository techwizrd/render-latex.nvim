local Config = require("render_latex.config")
local Util = require("render_latex.util")

local M = {}

local build_running = false
local build_error = nil
local install_running = false
local install_error = nil
local install_notified = false
local ready_listeners = {}
local progress_ids = {
  build = nil,
  install = nil,
}

local PROGRESS_SOURCE = "render-latex.nvim"
local PROGRESS_TITLES = {
  build = "render-latex worker build",
  install = "render-latex worker install",
}

local function progress_update(kind, message, status, percent)
  local opts = {
    kind = "progress",
    title = PROGRESS_TITLES[kind],
    source = PROGRESS_SOURCE,
    status = status,
    percent = percent,
  }
  if progress_ids[kind] ~= nil then
    opts.id = progress_ids[kind]
  end

  local ok, id = pcall(vim.api.nvim_echo, { { message } }, true, opts)
  if ok and type(id) == "number" then
    progress_ids[kind] = id
  end
end

local function emit_worker_ready(path, operation)
  for _, listener in ipairs(ready_listeners) do
    pcall(listener, path, operation)
  end
end

local function is_windows_sysname(sysname)
  return sysname:match("Windows") or sysname:match("MINGW") or sysname:match("MSYS")
end

local function worker_name()
  if is_windows_sysname(vim.uv.os_uname().sysname) then
    return "render-latex-worker.exe"
  end
  return "render-latex-worker"
end

local function executable_asset_name(system_key)
  local suffix = system_key:match("^windows") and ".exe" or ""
  return "render-latex-worker-" .. system_key .. suffix
end

local function asset_url_for_version(system_key, version)
  local release_path = version == "latest" and "latest/download" or ("download/" .. version)
  return ("https://github.com/%s/releases/%s/%s"):format(
    Config.install.repository,
    release_path,
    executable_asset_name(system_key)
  )
end

local function system_key_from_uname(sysname, machine)
  local os
  if sysname == "Darwin" then
    os = "macos"
  elseif sysname == "Linux" then
    os = "linux"
  elseif is_windows_sysname(sysname) then
    os = "windows"
  else
    return nil
  end

  local arch
  if machine == "x86_64" or machine == "amd64" or machine == "AMD64" then
    arch = "x64"
  elseif machine == "aarch64" or machine == "arm64" or machine == "ARM64" then
    arch = "arm64"
  else
    return nil
  end

  return os .. "-" .. arch
end

function M.system_key()
  local uname = vim.uv.os_uname()
  return system_key_from_uname(uname.sysname, uname.machine)
end

function M._system_key_from_uname(sysname, machine)
  return system_key_from_uname(sysname, machine)
end

function M.managed_worker_path()
  local system_key = M.system_key()
  if system_key == nil then
    return nil
  end
  return vim.fs.joinpath(
    vim.fn.stdpath("data"),
    "render-latex.nvim",
    "bin",
    Config.install.version,
    system_key,
    worker_name()
  )
end

function M.asset_url()
  local system_key = M.system_key()
  if system_key == nil then
    return nil
  end

  return asset_url_for_version(system_key, Config.install.version)
end

local function fallback_asset_url(system_key)
  if Config.install.version == "latest" and system_key == "linux-arm64" then
    return asset_url_for_version(system_key, "unreleased")
  end
  return nil
end

function M.local_worker_path()
  return vim.fs.joinpath(Util.root(), "target", "release", worker_name())
end

function M.worker_info()
  if Config.worker.bin ~= nil and Config.worker.bin ~= "" then
    local path = vim.fn.expand(Config.worker.bin)
    if vim.fn.executable(path) == 1 then
      return { path = path, source = "config" }
    end
    return {
      path = nil,
      source = "config",
      error = "configured worker.bin is not executable: " .. path,
    }
  end

  local managed_path = M.managed_worker_path()
  if managed_path ~= nil and vim.fn.executable(managed_path) == 1 then
    return { path = managed_path, source = "managed" }
  end

  local local_path = M.local_worker_path()
  if vim.fn.executable(local_path) == 1 then
    return { path = local_path, source = "local" }
  end

  if vim.fn.executable(worker_name()) == 1 then
    return { path = worker_name(), source = "path" }
  end

  return { path = nil, source = "missing" }
end

function M.resolve_worker_path()
  return M.worker_info().path
end

---@param notify boolean?
---@param callback? fun(path: string?, err: string?)
function M.build_worker(notify, callback)
  if build_running then
    if notify then
      Util.info("render-latex worker build is already running")
    end
    return
  end

  local command = { "cargo", "build", "--release", "--package", "render-latex-worker" }
  build_running = true
  build_error = nil
  if notify then
    progress_update("build", "Building render-latex worker...", "running", 5)
  end

  vim.system(command, { cwd = Util.root(), text = true }, function(result)
    vim.schedule(function()
      build_running = false
      local path = M.local_worker_path()
      if result.code ~= 0 then
        local stderr = vim.trim(result.stderr or "")
        build_error = stderr ~= "" and stderr or "build failed"
        if notify then
          progress_update(
            "build",
            "Failed to build render-latex worker" .. (stderr ~= "" and (": " .. stderr) or ""),
            "error",
            100
          )
          progress_ids.build = nil
        end
        if callback ~= nil then
          callback(nil, build_error)
        end
        return
      end

      build_error = nil
      if notify then
        progress_update("build", "Built render-latex worker", "success", 100)
        progress_ids.build = nil
      end
      emit_worker_ready(path, "build")
      if callback ~= nil then
        callback(path, nil)
      end
    end)
  end)
end

function M.on_worker_ready(listener)
  ready_listeners[#ready_listeners + 1] = listener
end

local function download_command(url, output)
  if vim.fn.executable("curl") == 1 then
    return { "curl", "-fL", "--retry", "2", "-o", output, url }
  end
  if vim.fn.executable("wget") == 1 then
    return { "wget", "-O", output, url }
  end
  if vim.fn.executable("powershell") == 1 then
    return {
      "powershell",
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
      ("Invoke-WebRequest -Uri %q -OutFile %q"):format(url, output),
    }
  end
  if vim.fn.executable("pwsh") == 1 then
    return {
      "pwsh",
      "-NoProfile",
      "-Command",
      ("Invoke-WebRequest -Uri %q -OutFile %q"):format(url, output),
    }
  end
  return nil
end

---@param notify boolean?
---@param callback? fun(path: string?, err: string?)
function M.install_worker(notify, callback)
  if install_running then
    if notify then
      Util.info("render-latex worker install is already running")
    end
    return
  end

  local final_path = M.managed_worker_path()
  local system_key = M.system_key()
  local url = M.asset_url()
  if final_path == nil or system_key == nil or url == nil then
    local err = "prebuilt worker is not available for this OS/architecture"
    install_error = err
    if notify then
      Util.error(err)
    end
    if callback ~= nil then
      callback(nil, err)
    end
    return
  end

  local parent = vim.fs.dirname(final_path)
  vim.fn.mkdir(parent, "p")
  local tmp_path = final_path .. ".tmp"
  local urls = { url }
  local fallback_url = fallback_asset_url(system_key)
  if fallback_url ~= nil then
    urls[#urls + 1] = fallback_url
  end
  local attempt = 1
  local command = download_command(urls[attempt], tmp_path)
  if command == nil then
    local err = "curl, wget, powershell, or pwsh is required to download the worker"
    install_error = err
    if notify then
      Util.error(err)
    end
    if callback ~= nil then
      callback(nil, err)
    end
    return
  end

  install_running = true
  install_error = nil
  if notify then
    progress_update("install", "Installing render-latex worker...", "running", 5)
  end
  local function run_download()
    command = download_command(urls[attempt], tmp_path)
    vim.system(command, { text = true }, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          local stderr = vim.trim(result.stderr or "")
          local err = "failed to download render-latex worker"
          if stderr ~= "" then
            err = err .. ": " .. stderr
          end
          if urls[attempt + 1] ~= nil then
            pcall(vim.fn.delete, tmp_path)
            attempt = attempt + 1
            run_download()
            return
          end
          install_running = false
          install_error = err
          pcall(vim.fn.delete, tmp_path)
          if notify then
            progress_update("install", err, "error", 100)
            progress_ids.install = nil
          end
          if callback ~= nil then
            callback(nil, err)
          end
          return
        end

        install_running = false
        if not final_path:match("%.exe$") then
          pcall(vim.uv.fs_chmod, tmp_path, tonumber("755", 8))
        end
        pcall(vim.fn.delete, final_path)
        local rename_ok, rename_err = vim.uv.fs_rename(tmp_path, final_path)
        if not rename_ok then
          install_error = tostring(rename_err)
          if notify then
            progress_update(
              "install",
              "failed to install render-latex worker: " .. tostring(rename_err),
              "error",
              100
            )
            progress_ids.install = nil
          end
          if callback ~= nil then
            callback(nil, tostring(rename_err))
          end
          return
        end

        if notify then
          progress_update("install", "Installed render-latex worker", "success", 100)
          progress_ids.install = nil
        end
        emit_worker_ready(final_path, "install")
        if callback ~= nil then
          callback(final_path, nil)
        end
      end)
    end)
  end

  run_download()
end

---@param callback? fun(path: string?, err: string?)
function M.ensure_installed_async(callback)
  if not Config.install.auto or install_running or M.resolve_worker_path() ~= nil then
    return
  end
  M.install_worker(false, function(_, err)
    if err ~= nil and not install_notified then
      install_notified = true
      Util.warn(
        "render-latex worker install failed. Run :RenderLatex install or :RenderLatex doctor."
      )
    end
    if callback ~= nil then
      callback(M.resolve_worker_path(), err)
    end
  end)
end

function M.status()
  local info = M.worker_info()
  return {
    path = info.path,
    source = info.source,
    system = M.system_key(),
    repository = Config.install.repository,
    version = Config.install.version,
    asset_url = M.asset_url(),
    building = build_running,
    installing = install_running,
    build_error = build_error,
    last_error = install_error,
    path_error = info.error,
  }
end

---@return string?
function M.ensure_worker_path()
  return M.resolve_worker_path()
end

function M.reset_for_tests()
  build_running = false
  build_error = nil
  install_running = false
  install_error = nil
  install_notified = false
  ready_listeners = {}
  progress_ids = {
    build = nil,
    install = nil,
  }
end

return M
