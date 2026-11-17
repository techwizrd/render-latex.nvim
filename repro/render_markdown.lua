local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
package.path = root .. "/?.lua;" .. package.path

local common = require("repro.common")

common.bootstrap_lazy("render-latex-render-markdown-repro")

require("lazy").setup({
  spec = {
    {
      "nvim-treesitter/nvim-treesitter",
      -- The default branch, main, needs Neovim 0.12 and the tree-sitter CLI. The
      -- archived master branch still runs on Neovim 0.10 and 0.11.
      branch = vim.fn.has("nvim-0.12") == 1 and "main" or "master",
      lazy = false,
      config = function()
        local langs = { "html", "latex", "markdown", "markdown_inline", "yaml" }
        -- Pick the API from the checkout, since an existing clone may be on either branch
        local ok_configs, configs = pcall(require, "nvim-treesitter.configs")
        if ok_configs then
          local parsers = require("nvim-treesitter.parsers")
          local needed = {}
          for _, lang in ipairs(langs) do
            if not parsers.has_parser(lang) then
              needed[#needed + 1] = lang
            end
          end
          if #needed > 0 then
            pcall(vim.cmd, "TSInstallSync " .. table.concat(needed, " "))
          end
          configs.setup({
            ensure_installed = {},
            highlight = { enable = false },
          })
        else
          -- main skips installed parsers and leaves highlighting off unless it is started
          pcall(function()
            require("nvim-treesitter").install(langs):wait(300000)
          end)
        end
        -- Keep this repro focused on render-markdown + render-latex overlap. On some
        -- Neovim nightly / nvim-treesitter combinations, Markdown language injections
        -- can fail before either plugin gets to render anything.
        vim.treesitter.query.set("markdown", "injections", "")
        vim.treesitter.query.set("markdown_inline", "injections", "")
      end,
    },
    {
      "nvim-mini/mini.nvim",
      lazy = false,
      config = function()
        local icons = require("mini.icons")
        icons.setup({})
        icons.mock_nvim_web_devicons()
      end,
    },
    {
      "MeanderingProgrammer/render-markdown.nvim",
      lazy = false,
      dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.nvim" },
      opts = {
        enabled = true,
        latex = {
          enabled = false,
        },
        yaml = {
          enabled = false,
        },
      },
      init = function()
        vim.api.nvim_create_autocmd("VimEnter", {
          once = true,
          callback = function()
            vim.notify(
              "render-markdown.nvim is active with latex.enabled=false so render-latex owns math rendering. Edit repro/render_markdown.lua to set latex.enabled=true when intentionally probing conflicts.",
              vim.log.levels.WARN,
              { title = "render-markdown repro" }
            )
          end,
        })
      end,
    },
    common.render_latex_spec(),
  },
})

common.default_keymaps()
vim.keymap.set(
  "n",
  "<leader>rm",
  "<cmd>RenderMarkdown toggle<cr>",
  { desc = "Toggle render-markdown" }
)
