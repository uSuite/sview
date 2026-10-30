# Changelog

Versions follow semver. Each release lists what a user notices; docs/DECISIONS.md has the reasoning.

## 0.2.1 (2026-10-30)

No app change. The family's branding note moved to scommon's `brand/`; docs/04-branding.md points there.

## 0.2.0 (2026-10-30)

- sView > Settings… (`cmd-,`): every config option as a control, Import Config (the old files kept as `.bak`), Export Config, Open Config Folder and the problems in the files. Open Config Folder loses `cmd-,`. The config zip now comes from scommon's `ConfigArchive`, the same one sNotate uses.
- Published as `uSuite/sview`: the bundle id is now `io.github.usuite.sview`, so window positions and Open Recent start fresh; config in `~/.config/sview/` is unchanged. A clone builds on its own, taking scommon 0.3.0 from GitHub.
- The title shows the step of a timestamp capture with any lower-case prefix, such as sCapture's `scap-`.

## 0.1.0 (2026-10-25)

First release: a keyboard-first image viewer that replaces qView for opening photos and walking PoC screenshot folders.

- Open from Finder, `open -a`, drag and drop, the `sview` command (with `-` for stdin) and Open Recent; optional reopen of the last image.
- Window-size decoding on background threads, neighbour preloading, a bounded cache and display-ready images: about 210 ms to the first image, 16 ms to the next.
- All ImageIO formats with EXIF orientation, animated GIF, APNG and WebP with pause and frame step, in-window errors and Quick Look for the rest.
- Zoom modes anchored at the cursor, pan, rotate, flip, backgrounds, fullscreen and theatre mode; optional window sizing to the image and click-to-navigate.
- Vim keys with counts, multi-key bindings, repeat, filter, marks and a `:` line with tab completion; every command in the menu bar.
- Sibling, parent and child folder moves, recursive mode, a thumbnail strip, a folder sidebar with counts and a folder watch for new captures.
- Copy, reveal, open with, rename, trash with undo, marked-name export and side by side compare.
- Plain-text config and keymap in `~/.config/sview/`, reloaded on change; the keymap file applies over the defaults.
- PoC helpers: case and step in the title, the memo pane and `:run` hooks.
