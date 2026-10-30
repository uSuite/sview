# sView: backlog

sView ("super-fast view") is a macOS-native image viewer in the spirit of qView: no chrome, instant open, keyboard first. Two use cases drive the priorities: quick-look any photo from Finder or the terminal, and browsing a PoC evidence tree (`poc-<product>/poc-<product>-<area>-<action>/*.png`, one folder per test case, 5 to 30 captures each, memo `<case-id>.md` beside the images).

Priorities: P0 is the MVP that replaces qView for daily use, P1 makes it better than qView for the PoC workflow, P2 is nice to have, P3 is parked. IDs are stable; reorder by editing priority, not IDs.

## Non-goals

- No editing beyond lossless rotate/flip for display; no filters, LUTs, RAW development, upscaling.
- No video playback, no Photos library integration, no cloud, no accounts.
- No Windows or Linux build; the point is to use Apple frameworks fully.
- No plugin system in v1; the keymap and command set are the extension points.

## E1 Core viewing (P0)

- SV-101 Open an image from Finder (double-click, Open With), from `sview <path>` on the command line, and by drag and drop onto the window or Dock icon. Opening a folder opens its first image.
- SV-102 First pixels on screen in under 100 ms for a 4 MB JPEG on Apple Silicon (cold app launch under 300 ms). Decode on a background queue, never block the main thread.
- SV-103 Downsampled decode for display: decode at the size the window needs (ImageIO thumbnail-with-transform), full-resolution decode only when zoomed past 1:1.
- SV-104 Preload the previous and next N images (N configurable, default 2) and keep a bounded decoded-image cache (memory budget configurable, default 512 MB).
- SV-105 Zoom modes: fit to window, fit width, fit height, actual size (1:1), free zoom with + / - and trackpad pinch; zoom anchored at cursor; HiDPI correct (points vs pixels).
- SV-106 Pan by hjkl, arrow keys, trackpad scroll and mouse drag when the image is larger than the window.
- SV-107 Rotate 90 degrees left/right and flip horizontal/vertical for the current view; honour EXIF orientation on load.
- SV-108 Animated GIF/WebP/APNG playback with play/pause and frame step.
- SV-109 Formats: everything ImageIO decodes on the host (JPEG, PNG, GIF, TIFF, BMP, HEIC/HEIF, WebP, AVIF, JPEG XL, PSD flattened, camera RAW through Core Image). Unsupported files show a clear in-viewport message, never a modal.
- SV-110 Background colour and checkerboard for transparency, configurable; auto light/dark follows the system appearance.
- SV-111 Fullscreen (native) and a borderless "theatre" mode; window title shows `name  i/N  WxH  size` and can be hidden.

## E2 Folder navigation (P0/P1)

- SV-201 (P0) Next/previous image within the current folder, with optional wrap-around; first/last image.
- SV-202 (P0) Sorting: natural name (so `case-02` precedes `case-10`), modification date, size, type; ascending/descending; remembered per session.
- SV-203 (P0) Skip hidden files, `._` AppleDouble files and non-image files silently.
- SV-204 (P1) Sibling-folder navigation: jump to the first image of the next/previous sibling folder (sorted like files). This is the PoC case-to-case move (`poc-demo-vm-stop` to `poc-demo-vm-tag`) without touching the mouse.
- SV-205 (P1) Parent-folder jump and "enter sub-folder" so a tree like `poc-demo/` can be walked entirely from the keyboard; optional recursive mode flattens the tree into one sequence.
- SV-206 (P1) Thumbnail strip (bottom or side) toggled by key, lazy thumbnails from ImageIO, current item highlighted, click or key to jump.
- SV-207 (P1) Folder sidebar (tree of sibling and child folders with image counts) toggled by key; typing filters it.
- SV-208 (P1) Watch the current folder with FSEvents: new captures appear at the right sorted position, deleted ones disappear, without reload or renumbering.
- SV-209 (P2) Recent files and recent folders list; reopen last session on launch (optional).
- SV-210 (P2) Open archives (ZIP, CBZ) read-only as virtual folders.

## E3 Vim-inspired control (P0/P1)

Keymap is a plain-text file the user edits; defaults below are the shipped keymap and follow nsxiv where sensible so muscle memory transfers.

- SV-301 (P0) Core keys: `n`/`p` or `space`/`shift-space` next/previous; `j`/`k`/`h`/`l` pan (when zoomed) and next/previous (when not); `gg`/`G` first/last; `+`/`-` zoom; `=` fit; `e` actual size; `<`/`>` rotate; `f` fullscreen; `q` quit; `r` reload; `i` info overlay; `t` thumbnails; `?` key help overlay.
- SV-302 (P0) Count prefix: `5n`, `3j`, `20G` (go to image 20).
- SV-303 (P1) Folder keys: `]` / `[` next/previous sibling folder, `-` or `..` parent folder, `o` enter folder under cursor in the sidebar.
- SV-304 (P1) Command line `:` with commands `:N` (go to image N), `:sort name|date|size [desc]`, `:cd <path>` with tab completion, `:set <option> <value>`, `:map <keys> <command>`, `:reveal`, `:trash`, `:rename <new>`, `:q`.
- SV-305 (P1) `/` filter the current folder by substring or regex, `n`/`N` within the filter, `Esc` clears.
- SV-306 (P1) Marks: `m` toggle mark on the current image, `M` mark all, `'` jump between marked, marked set can be trashed, copied as paths or revealed in Finder together. Fits the PoC step "delete wrong captures before running the rename script".
- SV-307 (P1) `yy` copy file path, `yi` copy image to clipboard, `yn` copy file name; `R` reveal in Finder; `O` open with (default app chooser); `dd` move to trash with undo (`u`).
- SV-308 (P2) `.` repeat last command; `:map`-defined macros persisted to the keymap file.
- SV-309 (P2) Mouse is optional but complete: scroll wheel next/previous or zoom (configurable), click left/right half of the viewport to navigate (qView 2025 feature), double-click toggles fit/actual, right-click context menu with the same commands.
- SV-310 (P0, bug) The `?` help panel owns input like the sidebar: wheel and trackpad scroll it, `j`/`k`, ctrl-d/u, space, `gg`/`G` move inside it, `?`, `q` and esc close it, and the viewer behind it does not react. See FIXME-1 in `03-plan-claude-code.md`.

## E4 Information and utilities (P1)

- SV-401 Info overlay (`i`): file name, index i/N, pixel size, file size, dates, colour space, bit depth, EXIF basics (camera, lens, exposure, GPS present yes/no), folder path. Cycles off / compact / full.
- SV-402 Memo pane: when `<folder-name>.md` exists beside the images (the PoC memo), `I` shows it rendered or as plain text in a side pane with the image reference for the current file highlighted.
- SV-403 Slideshow with configurable interval, `Enter` starts, any navigation key stops.
- SV-404 Rename current file in place (`:rename`, `cw` opens the prompt pre-filled with the stem) without losing position in the sequence.
- SV-405 Quick Look passthrough (`space` long press or `:ql`) for file types sView does not render.
- SV-406 Zoom level indicator and a one-second toast for actions (copied, trashed, sorted by ...), no sound.

## E5 App shell and platform (P0/P1)

- SV-501 (P0) Native menu bar with every command listed and its key shown; standard Open, Open Recent, Window and Help menus; About box with version and licence.
- SV-502 (P0) Register UTIs so sView appears in Finder's Open With for all supported image types and can be set as the default viewer.
- SV-503 (P0) Settings as plain text in `~/.config/sview/config`, hot-reloaded; no settings window in v1, `:set` edits the file; `:export` zips the config directory for transfer or archive.
- SV-504 (P0) Keymap file `~/.config/sview/keymap`, one binding per line, shipped default copied on first run, `:map` appends to it.
- SV-505 (P0) `sview` command-line launcher (symlink or small shell script installed by `make install`) that opens files or a folder in the running instance; `sview -` reads paths from stdin.
- SV-506 (P1) Multiple windows, one folder sequence per window; `cmd-n` opens the current image in a second window for side by side comparison.
- SV-507 (P1) Remember window size and position; option to size the window to the image on open (qView behaviour) or keep a fixed window.
- SV-508 (P1) Signed and notarised `.app`, distributed as a zip on GitHub Releases and a Homebrew cask tap; universal binary (arm64 + x86_64).
- SV-509 (P2) Sparkle-style update check, opt-in, or simply a "new version available" check against GitHub Releases.
- SV-510 (P2) Localisation scaffolding (English first, Vietnamese second).
- SV-511 (P1) Settings window (`cmd-,`), the macOS Settings look: every config option as a control, Import Config (the zip's files checked first, the replaced ones kept as `.bak`), Export Config, Open Config Folder and the problems in the files. It writes the same config lines `:set` writes; hooks and keys stay in the text files. Supersedes SV-503's "no settings window in v1". Done 2026-10-30.

## E6 PoC evidence helpers (P1/P2, Sam-specific, keep optional)

- SV-601 (P1) Case folder awareness: when the folder name matches `^poc-[a-z0-9-]+$`, the title shows the case id and the step number parsed from `<case-id>-<nn>.png` or the capture timestamp from `<tool>-YYYY-MM-DD-HHMMSS.png` (`scap-` from sCapture).
- SV-602 (P1) Marked-set export: write the marked file names to the clipboard or a text file so the rename script's exclusions or the memo's image list can be built from a viewing pass.
- SV-603 (P2) Folder action hook: `:run <name>` executes a user-defined shell command from the config with `$FILE`, `$FOLDER`, `$MARKED` substituted, for example `python3 ../report.py --dry-run`. Output shown in a scrollable pane.
- SV-604 (P2) Side-by-side compare of two marked images (synced zoom and pan) for before/after captures.
- SV-605 (P3) Memo editing in place (replace the `- description` placeholders while viewing) and Typst export; parked; sNotate owns the memo and its Typst export.

## E7 Performance, quality, tooling (continuous)

- SV-701 Benchmark script: cold launch to first frame, next-image latency at 1x and 4x zoom, memory after browsing 500 images; results in `bench/RESULTS.md` per commit that touches loading.
- SV-702 Unit tests for the core library (sorting, navigation, filter, keymap parser, command dispatch, cache eviction) run with `swift test`; no UI needed.
- SV-703 Smoke test script: launch the app on a fixture folder, drive it with `osascript`/`cliclick`, take a `screencapture` of the window and compare against a reference within tolerance.
- SV-704 Crash-free on the hostile fixture set: zero-byte file, truncated JPEG, 20k x 20k PNG, 500-frame GIF, 10,000-file folder, folder deleted while viewing, file replaced while viewing.
- SV-705 Instruments profile (Time Profiler, Allocations) once per milestone; no main-thread decode, no retain cycles in the cache.
- SV-706 Energy: idle app uses 0% CPU (no polling; FSEvents and timers only when needed).

## Ideas parked (P3)

- Colour management toggles (display P3 vs sRGB), HDR tone mapping for HEIC/AVIF HDR.
- Per-folder sort and zoom memory in a dotfile (`.sview`) inside the folder, git-friendly.
- Trash directory browsing and restore.
- iPad companion through Catalyst.
- An `sview --json` inspection mode that prints metadata for scripts.
