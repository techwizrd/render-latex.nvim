# Contributing

Thanks for taking the time to improve `render-latex.nvim`. The project is small enough that a good first contribution can still make a visible difference, and the main rule is simple: keep the editing experience fast, predictable, and kind to users.

This plugin sits in the middle of a few sensitive things: Markdown parsing, terminal image rendering, tmux behavior, and other Markdown plugins. Changes should be boring, well-tested, and easy for the next maintainer to reason about.

## Quick Development Setup

You will need:

- Neovim 0.10+ for the runtime target. CI also tests newer stable versions and nightly.
- Rust stable for the worker.
- Go for the pinned `actionlint` target.
- `stylua` for Lua formatting.
- `lua-language-server` for type checking.
- `prek` if you want local hooks.
- A Kitty graphics-compatible terminal or Neovim image API support for manual image-rendering tests.

Install local hooks with:

```bash
prek install
```

Run the normal validation loop:

```bash
make format
make check
make smoke-repros
```

Build the worker when working on rendering behavior:

```bash
make build-worker
```

## Good First Contributions

Good first changes are usually small and user-visible:

- Improve docs or troubleshooting messages.
- Add a repro fixture for a Markdown pattern that should or should not render.
- Add regression coverage for a reported bug.
- Improve `:RenderLatex doctor` output when a failure is confusing.
- Tighten compatibility with `obsidian.nvim` or `render-markdown.nvim` without mutating their configs.

Avoid large rewrites unless there is a clear bug or maintenance problem. This project should remain approachable for junior maintainers.

## Repository Layout

- `lua/render_latex/`: plugin implementation.
- `plugin/render_latex.lua`: command registration and default setup entrypoint.
- `crates/render-latex-worker/`: Rust worker that renders LaTeX and writes PNG cache entries.
- `tests/`: Lua regression tests.
- `repro/`: manual and headless repro configs.
- `doc/render-latex.txt`: Vim help documentation.
- `assets/`: README and project media.
- `.github/workflows/`: CI and release workflows.

## Common Commands

```bash
make format
make check
make build-worker
make smoke-repros
```

Useful individual targets:

- `make test`: run Lua tests.
- `make lint`: check Lua formatting.
- `make actionlint`: lint GitHub Actions workflows.
- `make typecheck`: run LuaLS diagnostics.
- `make clippy`: run Rust lints.
- `make rust-test`: run Rust worker tests.
- `make smoke-health`: run the headless health check.
- `make smoke-help`: verify `:help render-latex` opens.

## Manual Repros

Base Markdown repro:

```bash
nvim -u repro/repro.lua repro/sample.md
```

Obsidian compatibility repro:

```bash
nvim -u repro/obsidian.lua repro/obsidian-vault/index.md
```

render-markdown compatibility repro:

```bash
nvim -u repro/render_markdown.lua repro/render-markdown-sample.md
```

Long-note performance repro:

```bash
nvim -u repro/long_note.lua repro/long-note.md
```

Solarized Light theme repro:

```bash
nvim -u repro/light_theme.lua repro/sample.md
```

Headless aggregate smoke suite:

```bash
make smoke-repros
```

## Worker Development

The worker is a persistent Rust process using framed stdio messages. It renders display equations, keeps hot in-memory state, and writes PNG cache files.

Build it locally:

```bash
make build-worker
```

Run it directly for debugging:

```bash
make run-worker
```

Normal users should not need Rust. The plugin downloads prebuilt workers from GitHub releases when available, so avoid adding source-build requirements to normal install paths.

## Compatibility Policy

`render-latex.nvim` should compose with Markdown plugins instead of rewriting their state.

- Do not mutate `obsidian.nvim` or `render-markdown.nvim` configuration.
- Keep compatibility probing out of the render hot path.
- Report likely conflicts in `:RenderLatex status`, `:RenderLatex doctor`, and `:checkhealth render_latex`.
- For `render-markdown.nvim`, recommend `latex = { enabled = false }`.

## Performance Expectations

Rendering should never make normal editing feel stuck.

- Do not run worker builds, network downloads, or slow scans in the render path.
- Keep render work asynchronous or visible-range limited.
- Prefer cached state over repeated full-buffer work.
- Add tests when changing detection, rendering invalidation, or visible-range behavior.
- Run the long-note repro for changes that touch scanning, annotation, viewport, or render scheduling.

## Install And Release Assets

The runtime installer expects direct executable release assets with these names:

- `render-latex-worker-linux-x64`
- `render-latex-worker-linux-arm64`
- `render-latex-worker-macos-x64`
- `render-latex-worker-macos-arm64`
- `render-latex-worker-windows-x64.exe`

The release and unreleased workflows upload `SHA256SUMS`. The installer does not verify checksums yet; let's keep this as a future hardening task unless release security requirements change.

## Release Checklist

Before tagging a release:

1. Run `make format`.
2. Run `make check`.
3. Run `make smoke-repros`.
4. Push to GitHub and verify CI on hosted runners.
5. Create an RC tag such as `v0.1.0-rc1`.
6. Confirm release assets and `SHA256SUMS` are uploaded.
7. Test `:RenderLatex install` from a clean install against the release.
8. Smoke-test lazy.nvim with `{ "techwizrd/render-latex.nvim", ft = "markdown", opts = {} }`.
9. Smoke-test `vim.pack.add({ "https://github.com/techwizrd/render-latex.nvim" })`.
10. Test Windows worker download and launch when possible.
11. Check macOS command-line download behavior for Gatekeeper/quarantine issues when possible.

## CI Notes

CI runs Lua/Neovim tests on Linux and worker builds on Linux, macOS, and Windows. The release workflow publishes stable tagged assets, and the unreleased workflow refreshes rolling prerelease assets on pushes to `main`.

`Cargo.lock` is committed intentionally so worker release builds are reproducible.

## Coding Guidelines

- Prefer small, direct changes over clever abstractions.
- Delete code when possible.
- Keep functions boring and obvious unless abstraction clearly removes duplication.
- Preserve graceful fallback to raw text or inline fallback when image rendering is unavailable.
- Keep user-facing diagnostics actionable and low-noise.
- Be careful with tmux and terminal behavior; surprising external mutation should be opt-in.
- Add regression tests for behavior changes and performance-sensitive render-path changes.

## Asking Questions

If you are unsure whether a change fits the project, open an issue or draft PR with the smallest repro you have. A clear failing Markdown snippet is often more useful than a large proposed solution.

## License

Apache-2.0
