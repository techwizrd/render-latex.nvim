local subcommands = {
  enable = function()
    require("render_latex").enable()
  end,
  disable = function()
    require("render_latex").disable()
  end,
  toggle = function()
    require("render_latex").toggle()
  end,
  refresh = function()
    require("render_latex").refresh()
  end,
  build = function()
    require("render_latex.install").build_worker(true)
  end,
  install = function()
    require("render_latex.install").install_worker(true)
  end,
  status = function()
    require("render_latex").status()
  end,
  doctor = function()
    require("render_latex").doctor()
  end,
  tmux_check = function()
    require("render_latex").tmux_check()
  end,
  tmux_setup = function()
    require("render_latex").tmux_setup()
  end,
  equation_debug = function()
    require("render_latex").equation_debug()
  end,
  equation_rerender = function()
    require("render_latex").equation_rerender()
  end,
  equation_toggle = function()
    require("render_latex").equation_toggle()
  end,
  equation_source = function()
    require("render_latex").equation_source()
  end,
}

local subcommand_keys = vim.tbl_keys(subcommands)
table.sort(subcommand_keys)

vim.api.nvim_create_user_command("RenderLatex", function(opts)
  local name = opts.args ~= "" and opts.args or "toggle"
  local subcommand = subcommands[name]
  if subcommand == nil then
    vim.notify(("render-latex.nvim: invalid subcommand '%s'"):format(name), vim.log.levels.ERROR)
    return
  end
  subcommand()
end, {
  nargs = "?",
  desc = "Render Markdown LaTeX equations as images",
  complete = function(arg_lead)
    return vim
      .iter(subcommand_keys)
      :filter(function(key)
        return key:find(arg_lead, 1, true) ~= nil
      end)
      :totable()
  end,
})

if not require("render_latex").did_setup then
  require("render_latex").setup()
end
