local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
package.path = root .. "/?.lua;" .. package.path

local common = require("repro.common")

common.bootstrap_lazy("render-latex-obsidian-repro")

require("lazy").setup({
  spec = {
    {
      "nvim-lua/plenary.nvim",
      lazy = false,
    },
    {
      "obsidian-nvim/obsidian.nvim",
      version = "*",
      lazy = false,
      dependencies = { "nvim-lua/plenary.nvim" },
      opts = {
        legacy_commands = false,
        workspaces = {
          {
            name = "repro",
            path = "/home/kunal/Projects/nvim-render-latex/repro/obsidian-vault",
          },
        },
      },
    },
    common.render_latex_spec(),
  },
})

common.default_keymaps()
