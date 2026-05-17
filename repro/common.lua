local M = {}

local source = debug.getinfo(1, "S").source:sub(2)
local plugin_root = vim.fn.fnamemodify(source, ":p:h:h")
local worker_bin = plugin_root .. "/target/release/render-latex-worker"

function M.bootstrap_lazy(stdpath_suffix)
  vim.env.LAZY_STDPATH = vim.fn.stdpath("data") .. "/" .. stdpath_suffix

  local lazypath = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "lazy.nvim")
  if vim.fn.isdirectory(lazypath) == 0 then
    local out = vim.fn.system({
      "git",
      "clone",
      "--filter=blob:none",
      "https://github.com/folke/lazy.nvim.git",
      lazypath,
    })
    if vim.v.shell_error ~= 0 then
      error("Failed to clone lazy.nvim: " .. out)
    end
  end

  vim.opt.runtimepath:prepend(lazypath)
  vim.opt.termguicolors = true
  vim.opt.conceallevel = 2
  vim.opt.concealcursor = "nc"
end

function M.render_latex_spec(extra_opts)
  return {
    dir = plugin_root,
    lazy = false,
    opts = vim.tbl_deep_extend("force", {
      worker = {
        bin = worker_bin,
      },
      render = {
        preset = "match_text",
        match_text_color = true,
        background = "transparent",
        match_text_size = true,
        text_scale = 1.0,
        scale = 1.5,
      },
    }, extra_opts or {}),
    init = function()
      vim.api.nvim_create_autocmd("VimEnter", {
        once = true,
        callback = function()
          local has_img = vim.ui.img ~= nil and type(vim.ui.img.set) == "function"
          vim.notify(
            table.concat({
              "render-latex repro loaded",
              "vim.ui.img: " .. tostring(has_img),
              "tmux: " .. tostring(vim.env.TMUX ~= nil),
              "term: " .. (vim.env.TERM or "unknown"),
              "backend: " .. require("render_latex.image_backend").status().name,
            }, "\n"),
            vim.log.levels.INFO,
            { title = "render-latex repro" }
          )
        end,
      })
    end,
  }
end

function M.default_keymaps()
  vim.keymap.set("n", "<leader>lr", "<cmd>RenderLatex refresh<cr>", { desc = "Refresh LaTeX" })
  vim.keymap.set("n", "<leader>lt", "<cmd>RenderLatex toggle<cr>", { desc = "Toggle LaTeX" })
  vim.keymap.set("n", "<leader>ls", function()
    print(vim.inspect(require("render_latex").status()))
  end, { desc = "LaTeX status" })
end

return M
