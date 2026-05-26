# render-latex.nvim

[![CI](https://github.com/techwizrd/render-latex.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/techwizrd/render-latex.nvim/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/techwizrd/render-latex.nvim)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io/)
[![Platforms](https://img.shields.io/badge/prebuilt-Linux%20%7C%20macOS%20%7C%20Windows-blue)](#requirements)
[![Status](https://img.shields.io/badge/status-early%20release-orange)](#status)

Fast display-math rendering for Markdown in Neovim, with inline math that stays smooth while editing.

![render-latex.nvim demo](assets/demo.png)

<p align="center">
  <a href="assets/demo-light-01.png">Light mode screenshot 1</a> · <a href="assets/demo-light-02.png">Light mode screenshot 2</a> · <a href="assets/demo-dark-02.png">Dark mode screenshot</a>
</p>

`render-latex.nvim` is for people who write notes, docs, research, or homework in Markdown and want equations to be readable without giving up plain-text editing.

Raw LaTeX stays in your buffer. Display equations render when your terminal supports images, and inline math stays lightweight and cursor-friendly. It also plays well with [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) and [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim/).

## Quickstart

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "techwizrd/render-latex.nvim",
  ft = "markdown",
  opts = {},
}
```

With `vim.pack` on Neovim versions that include it:

```lua
vim.pack.add({
  "https://github.com/techwizrd/render-latex.nvim",
})
```

Open a Markdown file with display math:

```markdown
$$
\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}
$$
```

The plugin sets itself up with useful defaults and installs the matching prebuilt worker in the background on first load. If anything looks off, run:

```vim
:RenderLatex doctor
:checkhealth render_latex
```

## Features

- Renders Markdown display math blocks like `$$ ... $$` and `\[ ... \]` as transparent PNG images.
- Keeps the buffer editable: raw LaTeX stays in the file, and the image is only the rendered view.
- Handles inline math like `$x^2$` with a fast conceal/highlight fallback instead of image flicker.
- Uses a persistent Rust worker that starts once, batches visible equations, and keeps a warm cache and directional prefetching.
- Installs the matching prebuilt worker automatically on common platforms, with a manual source-build path when needed.
- Chooses a safe image backend for Neovim image support or Kitty graphics, including tmux passthrough.
- Plays nicely with Markdown note-taking setups, like [`render-markdown.nvim`](https://github.com/MeanderingProgrammer/render-markdown.nvim) and [`obsidian.nvim`](https://github.com/epwalsh/obsidian.nvim), instead of trying to own the whole buffer.

The goal is intentionally narrow: make equations in Markdown easier to read in Neovim without replacing your Markdown renderer, note-taking setup, or LaTeX workflow.

## Requirements

- Neovim 0.10+ with `vim.system`, `vim.uv`, `vim.fs`, extmarks, and Treesitter APIs.
- A display-image backend: Neovim image API support or a Kitty graphics-compatible terminal.
- For tmux image rendering: `set -g allow-passthrough on`.
- Prebuilt workers are published with releases for Linux x64, macOS x64, macOS arm64, and Windows x64. Linux arm64 and Windows arm64 currently fall back to the rolling `unreleased` prerelease on `install.version = "latest"` until the next tagged release includes those assets.

Rust is only needed for development, source builds, or unsupported prebuilt platforms.

## Configuration

No configuration is required for the default experience. These are the most common optional settings:

```lua
require("render_latex").setup({
  render = {
    preset = "match_text", -- "compact" or "presentation"
    inline = "conceal", -- "content", "highlight", or false
    inline_symbols = true,
    hide_on_cmdline = false,
  },
})
```

For the best inline math fallback experience:

```lua
vim.opt.conceallevel = 2
vim.opt.concealcursor = "nc"
```

If you pin plugin versions, pin the worker release too:

```lua
require("render_latex").setup({
  install = { version = "v0.1.0" },
})
```

If you want rolling worker binaries from `main`, use the `unreleased` prerelease:

```lua
require("render_latex").setup({
  install = { version = "unreleased" },
})
```

## Useful Commands

- `:RenderLatex doctor` opens a readable diagnostics buffer.
- `:RenderLatex install` downloads the prebuilt worker for your platform.
- `:RenderLatex refresh` queues a fresh render for the current buffer.
- `:RenderLatex equation_toggle` toggles the current display equation between raw and rendered modes.
- `:RenderLatex tmux_check` checks tmux image-rendering settings.

Run `:help render-latex` for the full command and option reference.

## Compatibility

### obsidian.nvim

No special configuration is required. `render-latex.nvim` ignores YAML frontmatter, fenced code blocks, inline code spans, Obsidian comments, and Markdown indented code blocks. Display math inside Obsidian callouts and blockquotes is supported.

### render-markdown.nvim

Let `render-markdown.nvim` handle Markdown structure and let `render-latex.nvim` own LaTeX rendering:

```lua
require("render-markdown").setup({
  latex = { enabled = false },
})
```

`render-latex.nvim` does not mutate other plugins' configuration. `:RenderLatex status`, `:RenderLatex doctor`, and `:checkhealth render_latex` report likely conflicts.

### jupynvim experimental

`render-latex.nvim` has an experimental source integration for [`jupynvim`](https://github.com/sheng-tse/jupynvim). When a jupynvim notebook buffer is detected, display math inside Markdown cells is rendered as images. Code cells are ignored, and inline math in notebook Markdown cells is left to jupynvim for now.

Other plugins can expose Markdown-like regions through the experimental source API:

```lua
require("render_latex").register_source({
  name = "my-plugin",
  attach = function(bufnr)
    return true -- return true only for buffers this source owns
  end,
  display_ranges = function(bufnr)
    return {
      { start_row = 0, end_row = 10 },
    }
  end,
  revision = function(bufnr)
    return "optional-source-state-version"
  end,
  inline = false,
})
```

Use `revision` for non-incremental sources whose external state can change without buffer text changes.

This API is intentionally experimental and may change before `v1.0.0`.

## Troubleshooting

Start with `:RenderLatex doctor` or `:checkhealth render_latex`. They report the detected platform, worker path, image backend, tmux state, conceal settings, and integration warnings.

If worker auto-install fails because of a proxy, firewall, offline use, or unsupported platform:

```lua
require("render_latex").setup({
  install = { auto = false },
})
```

Then use one of these options:

- Run `:RenderLatex install` after network access is available.
- Run `:RenderLatex build` with a local Rust toolchain.
- Use `install = { version = "unreleased" }` if you want the rolling prerelease worker assets from `main`.
- Download or build the worker yourself and set `worker.bin = "/path/to/render-latex-worker"`.

Terminal support still matters after the worker is installed. Use Neovim's image API when available, or a Kitty graphics-compatible terminal. Inside tmux, set `set -g allow-passthrough on`.

## Acknowledgements

`render-latex.nvim` stands on other people's work. [RaTeX](https://github.com/erweixin/RaTeX) does the hard layout and rendering work in the Rust worker. [`render-markdown.nvim`](https://github.com/MeanderingProgrammer/render-markdown.nvim) and [`obsidian.nvim`](https://github.com/epwalsh/obsidian.nvim) shaped how this plugin approaches compatibility: it should complement Markdown and note-taking workflows, not fight them. Feedback and interest from [`r/neovim`](https://reddit.com/r/neovim) helped motivate me to get an initial release together.

## Status

This is an early release. The defaults are meant to be fast and friendly, but option names may still change before `v1.0.0`.

Before the first stable release, I still want to:

- [ ] Verify GitHub CI and release assets on Windows x64 and arm64.
- [x] Confirm `:RenderLatex install` works from a clean install.
- [x] Smoke-test the documented lazy.nvim and `vim.pack` setup paths.
- [x] Check whether downloaded workers hit Gatekeeper/quarantine issues on macOS.

After that, the main things I want to explore are:

- [x] Folding support.
- [ ] An experimental mode for rendering inline display math.
- [ ] SVG rendering, once Neovim or custom providers can handle it well.
- [ ] Moving more render-queue logic into the Rust worker.
- [ ] Worker-side parsing/indexing for large notes.
- [ ] Kitty placeholder-based rendering for better tmux and scroll behavior.
- [ ] Checksum verification for downloaded workers.
- [ ] Moving doctor/tmux diagnostic formatting out of `init.lua` if it keeps growing.

## Documentation

- Full docs: `:help render-latex`
- Contributing and development: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- License: Apache-2.0
