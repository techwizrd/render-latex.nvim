# render-latex.nvim Roadmap

## Quick Wins

1. [done] Add command-line and message-area suppression.
2. [done] Add `:RenderLatex tmux_check` for explicit tmux diagnostics.
3. [done] Improve tmux hook detection in health checks.
4. [done] Add equation-local rerender and debug commands.
5. [done] Avoid rerendering on focused-equation exit when the text hash is unchanged.
6. [done] Add a short rerender delay on equation exit to reduce visual popping.
7. [done] Show temporary virtual text while an edited equation is rerendering.

## Performance

1. [done] Avoid full-buffer rescans by tracking changed line ranges.
2. [done] Replace line scanning with Treesitter-based display-math detection.
3. [done] Cache parsed equation metadata in Lua.
4. [done] Batch worker render requests for visible equations.
5. [done] Prefetch equations more intelligently based on viewport and scroll direction.
6. [done] Reduce repeated PNG blob reads for visible equations.
7. [done] Compute render fingerprints once per render pass instead of per equation.
8. [done] Add degrade modes for very large markdown files.
9. [done] Add worker-side LRU memory limits.
10. [done] Add worker-side disk cache limits and eviction.

## UX

1. [done] Add image sizing presets like `match_text`, `compact`, and `presentation`.
2. [done] Improve theme integration beyond foreground color.
3. [done] Add inline math fallback behavior.
4. [done] Add manual per-equation raw/rendered toggle.
5. [done] Add hover or command-based “show source” behavior.
6. [done] Improve statusline/bottom-edge behavior further when an image does not fit.
7. [done] Hide images during cmdline and other temporary UI states.
8. [done] Add notebook-style polish like equation markers or numbering.

## Medium Refactors

1. [done] Build an incremental equation index per buffer.
2. [done] Track changed equations through `nvim_buf_attach`.
3. [done] Move more viewport and visibility logic into dedicated renderer helpers.
4. [done] Separate render invalidation, placement updates, and visibility suppression more cleanly.
5. [done] Improve multi-window focused-equation handling.

## Long-Term Architecture

1. Let the Rust worker own more render queue logic.
2. Explore a worker-side parser/indexer for large notes.
3. [done] Consider a more explicit backend/provider abstraction if additional image transports are needed.
4. Revisit SVG workflows when Neovim or custom providers can render them efficiently.
5. Explore kitty placeholder-based rendering for better tmux or scroll semantics.

## Initial Release Readiness

1. [done] Make display detection Markdown-aware: ignore fenced code blocks and do not render unclosed display delimiters.
2. [done] Remove synchronous worker auto-build from the render path; keep builds explicit or async so Neovim never freezes.
3. [done] Harden image placement: guard cache reads/backend calls, invalidate stale metadata, and avoid render-loop crashes.
4. [done] Add negative caching and warning throttling for invalid LaTeX so failed equations do not rerender repeatedly.
5. [done] Add nested config validation for render/image/worker options and enum values.
6. [done] Make backend selection explicit and safe: do not silently fall back to unsupported Kitty escape output.
7. [done] Optimize inline fallback for large files by caching inline detections or limiting work to visible ranges.
8. [done] Prune stale renderer state after edits so metadata and per-equation maps do not grow indefinitely.
9. [done] Decide whether tmux cleanup hooks should be opt-in, and document behavior clearly.
10. [done] Declare exact minimum Neovim/version/backend requirements and feature-gate unsupported versions gracefully.
11. [done] Add release smoke tests for worker startup, invalid equations, missing cache files, tmux/kitty status, and large-file behavior.

## Plugin Compatibility

1. [done] Keep `render-markdown.nvim` compatibility non-invasive: document `latex = { enabled = false }` and warn in health/status instead of mutating its config.
2. [done] Support Obsidian-style callouts/blockquotes with display math.
3. [done] Ignore YAML frontmatter, fenced code blocks, and inline code spans for math detection.
4. [done] Add `obsidian.nvim` detection to `:RenderLatex status` and health output.
5. [done] Expand render-markdown diagnostics with inspectability, recommendations, and less noisy fallback warnings.
6. [done] Ignore Obsidian comment blocks (`%% ... %%`) and Markdown indented code blocks.
7. [done] Add regression coverage for Obsidian comments, indented code, nested blockquotes, and punctuation-adjacent inline math.
8. [done] Add headless integration smoke targets for Obsidian and render-markdown repro configs.
9. [done] Add LazyVim-oriented render-markdown override docs.
10. [done] Consider a user-facing `:RenderLatex doctor` diagnostics scratch buffer after status/health data stabilizes.
11. [done] Keep all compatibility probing out of the render hot path; only status, health, and manual diagnostics may inspect other plugins.

## Release Polish

1. [done] Keep repro commands runnable headlessly so plugin-manager and scheduled-callback regressions are caught before release.
2. [done] Keep tmux documentation aligned with opt-in cleanup hook behavior.
3. [done] Document smoke targets for contributors and release checks.
4. [done] Add a single aggregate smoke target that opens every maintained repro.
5. [done] Include `:RenderLatex doctor` in smoke coverage.

## Release Docs And Diagnostics

1. [done] Add Vim help documentation for setup, commands, compatibility, and troubleshooting.
2. [done] Add health guidance when inline fallback is enabled but `conceallevel` prevents conceal rendering.
3. [done] Add a headless health smoke target for release checks.
4. [done] Keep README, help docs, and command names aligned.

## First Release Checklist

1. [done] Add a root `LICENSE` file matching the Apache-2.0 license declared in Cargo metadata.
2. Push the repository to `https://github.com/techwizrd/render-latex.nvim` and verify GitHub CI on real Linux, macOS, and Windows runners.
3. Create a test release tag such as `v0.1.0-rc1` and confirm the release workflow uploads worker assets and `SHA256SUMS`.
4. Verify `:RenderLatex install` downloads and launches the released worker from a clean install.
5. Smoke-test lazy.nvim setup with `{ "techwizrd/render-latex.nvim", ft = "markdown", opts = {} }`.
6. Smoke-test `vim.pack` setup with `vim.pack.add({ "https://github.com/techwizrd/render-latex.nvim" })`.
7. Test at least Linux and one macOS or Windows machine manually; prioritize PowerShell download and worker launch on Windows.
8. [done] Decide whether Linux ARM64 is supported in `v0.1.0`; use source-build fallback until a real release asset exists.
9. [done] Advise pinned plugin users to set `install.version = "v0.1.0"` instead of using `latest`.
10. [done] Add troubleshooting docs for failed auto-install: proxy/firewall/offline use, `install.auto = false`, manual `:RenderLatex install`, source `:RenderLatex build`, and custom `worker.bin`.
11. [done] Document terminal/backend support clearly, especially Neovim image API support, Kitty-compatible terminals, and tmux `allow-passthrough`.
12. Check macOS downloaded-worker behavior for Gatekeeper/quarantine issues when installed via command-line download.
13. [done] Confirm `Cargo.lock` is committed for reproducible release builds.
14. [done] Add README badges after CI is green.
15. [done] Add an early-release/API-stability note if options or command names may still change.
16. Consider checksum verification for downloaded workers after the first release if install security becomes a priority.
17. Consider async `:RenderLatex build` later; keep it explicit and source-build oriented for the first release.
18. Consider moving doctor/tmux diagnostic formatting out of `init.lua` after release if maintainability work continues.

## Help Quality

1. [done] Generate Vim help tags for packaged docs.
2. [done] Add a headless smoke target that opens `:help render-latex`.
3. [done] Include help smoke coverage in aggregate repro smoke checks.
4. [done] Document help smoke checks for contributors.

## Release UX Goals

1. Rendering must never block normal editing; any expensive build, worker startup, parsing, or rendering work should be async or explicitly user-triggered.
2. Cursor movement and typing should stay smooth in large Markdown buffers; render work should be visible-range aware and debounced.
3. Failures should degrade gracefully to raw or inline text fallback without noisy repeated notifications.
4. Terminal/backend incompatibility should be detected early with actionable health output, not visual garbage.
5. Default behavior should feel polished: fast first render, stable scrolling, predictable editing reveal, and clear commands for recovery.

## Priority Order

1. [done] Treesitter-based math detection.
2. [done] Incremental equation indexing.
3. [done] Batched worker render requests.
4. [done] Worker cache limits and eviction.
5. [done] Better tmux diagnostics and hook checks.
6. [done] Cmdline/floating-window temporary image suppression.

## Notes

- Highest ROI: Treesitter plus incremental indexing.
- Highest UX impact: better tmux diagnostics and temporary UI suppression.
- Biggest long-term win: batching plus worker cache policy.
