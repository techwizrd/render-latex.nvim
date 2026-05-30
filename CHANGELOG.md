# Changelog

All notable changes to `render-latex.nvim` will be documented in this file.

This project follows a practical changelog format inspired by [Keep a Changelog](https://keepachangelog.com/). Version numbers will use semantic versioning once the first release is tagged.

## Unreleased

### Changed

- Added prebuilt worker support for Linux ARM64 / Asahi Linux.
- Added a temporary Linux ARM64 installer fallback from the latest release to the `unreleased` prerelease until the next tagged release publishes a Linux ARM64 worker asset.
- Switched non-tmux Kitty graphics detection from terminal-specific environment checks to a protocol probe with cached results.
- Made `:RenderLatex build` run asynchronously and refresh visible buffers through the same worker-ready path used by installs.
- Switched long-running worker build and install commands to native Neovim progress messages.
- Added a rolling `unreleased` GitHub prerelease workflow for non-tag `main` pushes.
- Requeued all visible buffers on `ColorScheme` so theme switches rerender visible equations automatically.
- Optimized scrolling by adding a lightweight `WinScrolled` refresh path, coalescing repeated scroll events, and batching Kitty placement updates.
- Added fold-aware visibility so equations inside closed folds stay hidden until the fold is opened again.
- Added virtual padding for inline math conceals in Markdown pipe tables so table borders keep their expected width more often.
- Improved first-run worker install scheduling so plugin-manager options can override defaults before automatic installs start.
- Improved worker error reporting and shutdown handling.
- Preferred Kitty graphics over the Neovim image API in tmux auto-detection when passthrough is available, while still falling back to `vim.ui.img` when Kitty is unavailable.
- Made Kitty backend probing more tolerant of slow terminal responses by increasing the timeout and retrying unsupported probe results.
- Allowed focused display equations to render in Normal mode on first view while preserving raw reveal behavior while editing.

### Fixed

- Fixed Ghostty and other Kitty graphics-compatible terminals being reported as unsupported outside tmux.
- Avoided noisy worker-unavailable warnings while a worker build is in progress.
- Fixed repro configs to resolve the plugin root relative to `repro/common.lua` instead of using a machine-specific absolute path.
- Fixed stale cached equations after line deletions, including deleting display math at end of file.
- Fixed render scheduling while floating UI is visible so work can still reach the worker while image placement stays suppressed.
- Fixed configured `worker.bin` status and health reporting when the configured path is not executable.
- Avoided repeated full-buffer inline fallback scans for buffers with no display equations.
- Fixed rendering startup when the `markdown_inline` Treesitter query/parser is unavailable by falling back to non-Treesitter display math detection.
- Fixed tmux backend diagnostics so passthrough-disabled sessions are reported clearly and explicit Kitty configuration can force passthrough when terminal markers are unavailable inside tmux.
- Fixed stuck worker requests by timing out hung requests, terminating stale worker handles safely, and scheduling bounded render retries after worker reset errors.
- Fixed tmux health and doctor diagnostics so they no longer claim Kitty passthrough is in use when the Neovim image backend is selected.
- Clarified doctor diagnostics by using `status` and `suggested action` labels instead of overloading `recommendation`.

## 0.1.0-rc2 - 2026-05-16

### Changed

- Split Rust checks out of the Neovim CI matrix so stable Neovim coverage only runs plugin tests.

### Fixed

- Fixed image backend tests on stable Neovim versions where `vim.ui.img` is unavailable.
- Avoided noisy first-run render warnings while the prebuilt worker is still installing in the background.

## 0.1.0-rc1 - 2026-05-16

### Added

- Added zero-config setup with background prebuilt worker installation.
- Added `:RenderLatex install` for manually downloading the platform worker.
- Added managed worker discovery under Neovim's data directory.
- Added GitHub CI and release workflows for Lua checks, worker builds, release assets, and checksums.
- Added `CONTRIBUTING.md` with development commands, repros, release notes, and compatibility policy.
- Added README badges and demo image.
- Added Apache-2.0 license file.
- Added installer and setup regression tests.

### Changed

- Reworked `README.md` to focus on fast user onboarding and clear troubleshooting.
- Made `setup()` idempotent so plugin-manager defaults and user overrides compose safely.
- Improved worker diagnostics in `:RenderLatex doctor` and `:checkhealth render_latex`.
- Improved render-path behavior so unsupported transient modes no longer clear cached state.
- Reduced repeated full-buffer work for visible-range inline math detection.
- Made worker shutdown quieter for intentional exits.
- Committed `Cargo.lock` for reproducible worker release builds.

### Fixed

- Preserved focused-equation dirty tracking while transient UI suppression is active.
- Avoided repeated inline fallback scans across multiple visible windows.
- Reported Linux ARM64 as unsupported for prebuilt worker downloads until a release asset exists.

## 0.1.0 - Upcoming

Initial public release target.

Expected highlights:

- Markdown display math rendering for `$$ ... $$` and `\[ ... \]` blocks.
- Lightweight inline math fallback for `$...$` and `\(...\)` spans.
- Persistent Rust worker backed by RaTeX.
- Neovim image API and Kitty graphics backend support, including tmux passthrough.
- Compatibility diagnostics for `obsidian.nvim` and `render-markdown.nvim`.
- Prebuilt workers published with releases for Linux x64, macOS x64, macOS arm64, and Windows x64.
