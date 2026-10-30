# sView: landscape

What exists today, what is worth copying, and where sView should differ. Written 2026-10-25 from the project pages and release notes linked at the bottom; version numbers will drift.

## qView in 5 lines

1. Free, open-source (GPLv3) image viewer in C++ on Qt, cross-platform (Windows, macOS, Linux), ~3.5k GitHub stars, 1,750+ commits; latest stable is 7.1 (July 2025) on Qt 6.8, with nightly builds and a Homebrew cask `qview`.
2. Design thesis is "practical and minimal": no toolbars, just the image and the title bar; opens almost instantly, switches images quickly, and keeps CPU and memory low thanks to multithreaded preloading of the neighbouring files.
3. Feature set stays viewer-only: folder navigation with sorting and "skip hidden files", animated GIF controls, rotate and mirror, slideshow, zoom modes, file history, drag and drop, delete to trash or permanently, reload, a context menu and a long list of configurable preferences and shortcuts.
4. Formats come from the Qt image plugins plus KImageFormats: BMP, GIF, JPEG, PNG, TIFF, WebP, HEIF/AVIF (since 4.0) and niche ones such as QOI, DDS, PFM; RAW support exists but has had display bugs when preloading.
5. Costs of the approach for a Mac user: a bundled Qt runtime and a non-native look, trackpad scroll/zoom detection that needed repeated fixes (7.1 added a manual override), 120+ open issues and part of the active development happening in a fork (jdpurcell/qView). This is the gap a Swift-native clone fills.

## Pixea in 5 lines

1. Proprietary macOS-only (11+) viewer and editor by ImageTasks, native on Apple Silicon and Intel; free tier plus a "Pixea Plus" subscription that unlocks most of the power features.
2. Pitch is a clean, minimal interface, speed, and on-device processing (privacy); it browses folders, the Photos library and ZIP/CBZ archives, with slideshow, theatre mode and duplicate search in the free tier.
3. Very broad format coverage: JPEG, HEIC, PNG, TIFF, JPEG XL, AVIF, PSD, WebP, GIF, BMP, many camera RAW types (ARW, NEF, CR3, ...) and common video containers; exports to ten image formats.
4. Keyboard model worth studying: W/A/S/D scroll, Z + click zoom, + / - zoom, arrows for previous/next image, up/down for frames, Enter slideshow, [ and ] rotate, \ fit to screen, 0 actual size; shortcut customisation is a Plus feature.
5. It has grown into a Lightroom-lite: LUT filters, curves, HSL, masks, reshape, 2x/4x upscaling, object removal, batch editing, ratings and labels, sorting and search. Good product, but editing is out of scope for sView and the thumbnail panel, status bar and sorting being paywalled is exactly what a small free tool can beat.

## What sView takes from each

| Aspect | qView | Pixea | sView |
| --- | --- | --- | --- |
| UI chrome | none, image + title bar | minimal, panels on demand | none by default; info overlay and thumbnail strip toggled by key |
| Speed trick | multithreaded preload of neighbours | native Apple frameworks | ImageIO downsampled decode + neighbour preload + decoded-image cache |
| Navigation | within one folder | folder, library, archive | within folder plus jump to sibling folder (the PoC case-folder use case) |
| Keys | configurable, arrow-centric | WASD + letters | vim grammar (hjkl, counts, `:` commands, marks) with a plain-text keymap file |
| Formats | Qt plugins | everything incl. RAW and video | whatever ImageIO decodes on the host macOS (JPEG, PNG, GIF, TIFF, HEIC, WebP, AVIF, JXL, RAW); no video |
| Licence | GPLv3 | proprietary + subscription | open source, permissive (MIT or Apache-2.0, to decide) |

## Other alternatives looked at

- nsxiv (Linux, X11, C, GPL): the reference for vim-style image viewing; its key grammar (n/p, hjkl, gg/G, +/-, counts, marks, thumbnail mode) is the model sView adapts rather than invents.
- qimgv (Qt, cross-platform, GPL): qView's closest sibling, faster folder view and video support, same Qt trade-offs.
- Xee³ (macOS, paid): long-running Mac viewer with archive browsing and many formats; closed, slow release cadence.
- Phoenix Slides (macOS, free): very fast fullscreen browser and slideshow with EXIF; old-school AppKit, minimal maintenance.
- Lyn (macOS, paid): lightweight browser and viewer aimed at photographers, EXIF and maps, Photos library access.
- LeafView (cross-platform, MIT): small open-source viewer with smooth zoom and grid view; useful as a feature checklist, not as a code base.
- ApolloOne and EdgeView (macOS, paid): Metal-accelerated viewers aimed at photographers and comic readers respectively; show that a native Mac viewer can be very fast.
- Preview and Quick Look (built in): the baseline every Mac user already has; sView must beat them on open latency, folder navigation and keyboard control, otherwise there is no reason to exist.

## Sources

- [qView on GitHub](https://github.com/jurplel/qview)
- [qView releases](https://github.com/jurplel/qView/releases/)
- [qView site](https://interversehq.com/qview/)
- [jdpurcell/qView fork release 2025-03-29](https://newreleases.io/project/github/jdpurcell/qView/release/v2025-03-29.c19b3ac)
- [Pixea](https://www.imagetasks.com/pixea/)
- [Pixea alternatives on AlternativeTo](https://alternativeto.net/software/pixea)
