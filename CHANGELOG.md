# Changelog

All notable changes to `render-latex.nvim` will be documented in this file.

This project follows a practical changelog format inspired by [Keep a Changelog](https://keepachangelog.com/). Version numbers will use semantic versioning once the first release is tagged.

## Unreleased

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
