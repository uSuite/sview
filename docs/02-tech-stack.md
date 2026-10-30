# sView: technology stack

Decision: Swift, SwiftUI for the shell, AppKit where SwiftUI is still thin (the image canvas, key handling, menus), Apple system frameworks for everything image-related, zero third-party dependencies in v1. Status: proposed 2026-10-25; the macOS floor (26) and config location (`~/.config/sview/`) were decided the same day, see `DECISIONS.md`.

## Why native Swift and not Rust (or Qt)

Rust was considered. For a viewer whose hot path is "decode file, upload to GPU, present", the decoder matters more than the language, and on macOS the fastest and broadest decoders are Apple's own (ImageIO, Core Image RAW), which Rust can only reach through C bindings. A Rust UI would need egui, Tauri or a Swift bridge, each adding a toolchain, a build time measured in minutes and a `target/` directory measured in gigabytes, for no native widgets in return. qView already demonstrates the cross-platform-toolkit trade: a bundled runtime, non-native trackpad behaviour and a look that is never quite Mac. Swift gives native menus, services, UTIs, Quick Look, sandbox-friendly file access and dark mode for free, compiles in seconds for a project this size, and ships a 5 to 10 MB `.app` with no runtime. Rust stays a candidate only for an optional offline helper (duplicate finder, batch metadata) if one ever becomes necessary, built separately and called as a process.

Pure AppKit (no SwiftUI) is the fallback if SwiftUI's key handling or window management gets in the way; the architecture below keeps the UI layer thin enough that swapping it is a bounded job.

## Frameworks

| Need | Framework | Notes |
| --- | --- | --- |
| Decode | ImageIO (`CGImageSource`) | `kCGImageSourceCreateThumbnailWithTransform` + `kCGImageSourceThumbnailMaxPixelSize` gives downsampled decode at the window size; `kCGImageSourceShouldCacheImmediately` for the full decode on a background queue. Handles JPEG, PNG, GIF, TIFF, BMP, HEIC, WebP (11+), AVIF (13+), JXL (14+). |
| RAW | Core Image `CIRAWFilter` | Lazy, only when ImageIO refuses the file. |
| Metadata | ImageIO `CGImageSourceCopyPropertiesAtIndex` | EXIF, TIFF, GPS dictionaries; no exiftool. |
| Display | Core Animation `CALayer.contents = CGImage` inside an `NSView` (layer-backed) | Zoom and pan are layer transforms, so navigation never re-decodes. Metal is not needed in v1; `CAMetalLayer` is the upgrade path for HDR. |
| Animation | ImageIO frame enumeration + `CADisplayLink` (macOS 14) | Frame delays from the container properties. |
| File types | UniformTypeIdentifiers | `UTType.image` conformance decides what is "an image"; declared in `Info.plist` for Open With. |
| Folder watch | `DispatchSource.makeFileSystemObjectSource` on the directory fd, FSEvents if recursive mode ships | Debounced rescan. |
| Shell | SwiftUI `App`, `WindowGroup`, `Settings` (unused in v1), `Commands` for the menu bar | Keeps menu definitions declarative and in one file. |
| Canvas and keys | `NSViewRepresentable` hosting a custom `NSView` that is first responder | Reliable `keyDown`, modifier flags, scroll and magnify gestures; SwiftUI `onKeyPress` (macOS 14) is used only for overlays. |
| State | Observation (`@Observable`) | Requires macOS 14. |
| Trash, reveal, open with | `FileManager.trashItem`, `NSWorkspace` | Standard behaviour, undo via the returned URL. |
| Quick Look | `QLPreviewPanel` | For files sView cannot render. |
| Tests | Swift Testing (or XCTest) | On the core library only; UI by smoke script. |

## Minimum macOS

macOS 26 Tahoe (decided 2026-10-25), arm64 only unless an Intel machine shows up. Apple's numbering jumped from 15 Sequoia to 26, so 26 is the current major and the only floor above 15 that exists. Benefits over a 14 floor: Xcode 26 and Swift 6.2 toolchain, Observation, `onKeyPress`, `CADisplayLink` on NSView, JPEG XL decode, Liquid Glass window chrome handled by the system, and no `#available` branches anywhere in the code base. Cost: nobody on Sequoia can run it, which is acceptable for a personal tool.

## Architecture: three layers, one direction

Dependencies point downward only. The core knows nothing about AppKit or SwiftUI, which is what makes it testable with `swift test` on any Mac and keeps a UI rewrite cheap.

```
App         sViewApp.swift, menus (Commands), file associations, launcher
UI          ImageCanvasView (NSView), overlays (SwiftUI), ThumbnailStrip, Sidebar, CommandLine
Core        SViewCore library: FolderModel, Sorter, Navigator, Filter, Marks,
            ImageLoader + ImageCache, Keymap parser, Command enum + Dispatcher,
            Config + Keymap file IO, PocCase (folder-name parsing)
```

Data, logic and control stay separate in Sam's sense: `FolderModel` is data (the sorted list of URLs and their state), `Navigator`/`Sorter`/`Filter` are pure logic over it, and `Dispatcher` is the single control point that maps a `Command` to a state change. The UI only renders state and forwards key events to the keymap. Every user-visible action is a `Command` case, so menus, keys, the `:` command line and tests all speak the same vocabulary.

## Configuration files

Plain text, git-friendly, owned parser, no TOML/YAML dependency.

- `~/.config/sview/config`: one `key value` per line, `#` comments. Example: `preload 2`, `cache_mb 512`, `wrap true`, `sort name`, `background auto`. The default config is embedded in the app and written out on first run, so the file documents itself. `:export` writes a zip of the directory (config, keymap, no state) for transfer to another machine.
- `~/.config/sview/keymap`: one binding per line, `<keys> <command> [args]`, same grammar as `:map`. Example: `]  folder-next`, `gg first`, `yy copy-path`, `:bench run-shell python3 ../report.py --dry-run`.
- Location is `~/.config/sview/` only (decided 2026-10-25), honouring `$XDG_CONFIG_HOME` when set. No `~/Library/Application Support` fallback: one place, Linux style, so the whole directory can be copied, archived or kept in a dotfiles repo. All paths and file names are lower-case with no white space.

Session state (window frame, recent files) is separate JSON via `Codable` in `~/.config/sview/state.json`; it is disposable and never hand-edited, and listed in the dotfiles `.gitignore`.

## Build and repository layout

The repo stays usable from the terminal, which is what Claude Code needs. No committed `.xcodeproj`: it is generated from a small YAML by XcodeGen, so diffs stay readable and merge conflicts in `project.pbxproj` never happen.

```
sview/
  Package.swift            SPM: library SViewCore + its tests (swift build / swift test)
  project.yml              XcodeGen spec for the sView.app target (depends on SViewCore)
  Sources/SViewCore/       pure Swift, no UI imports
  Sources/sView/           App + UI layers
  Tests/SViewCoreTests/
  Resources/               Assets.xcassets, Info.plist template, default config and keymap
  fixtures/                small images for tests and the hostile set (SV-704), git-lfs if large
  bench/                   benchmark script and RESULTS.md
  scripts/                 bundle.sh, smoke.sh, notarize.sh, install-cli.sh
  docs/                    these documents, DECISIONS.md
  Makefile                 build, run, test, bench, smoke, app, install, clean
  CLAUDE.md
```

Toolchain: Xcode 26 or newer (Swift 6.2 language mode, strict concurrency on for `SViewCore`, minimal for the UI target), XcodeGen via Homebrew, `xcodebuild -scheme sView -configuration Debug build` behind `make app`, `swift test` behind `make test`. Everything the plan asks Claude Code to run is a `make` target, so the commands are documented in one place and stable across sessions.

Distribution: Developer ID signing and notarisation through `notarytool` in `scripts/notarize.sh`, zip on GitHub Releases, Homebrew cask in the `uSuite/homebrew-tap` tap. The App Store is a non-goal (sandbox and no `~/.config`).

## Alternatives considered

| Option | Verdict |
| --- | --- |
| Rust + egui/iced | Native decoders unreachable without bindings, no native widgets, heavy toolchain. No. |
| Rust core + Swift UI via swift-bridge or C FFI | Two toolchains for one person; the core is small enough in Swift. No for v1. |
| Tauri / Electron | Web view cannot hit the latency target and doubles memory. No. |
| Qt (fork qView) | Already exists, not native; the reason for the project. No. |
| Pure AppKit, no SwiftUI | Viable; kept as the fallback. The SwiftUI shell is a thin convenience for menus and overlays. |
| Metal from day one | Premature; `CALayer` with a `CGImage` is GPU-composited already. Revisit for HDR. |
| Third-party TOML/YAML parser | 30 lines of owned `key value` parsing beats a dependency. No. |

## Risks

- SwiftUI focus and first-responder quirks on macOS can eat key events; mitigated by keeping all key handling in the `NSView` canvas and making it first responder on every window activation.
- ImageIO behaviour differs per macOS version (WebP, AVIF, JXL availability); the format list is probed at runtime and the unsupported-file message says why.
- Strict concurrency in Swift 6 can slow early progress; `SViewCore` is strict from the start (small, pure), the UI target starts in minimal checking and tightens later.
- Notarisation and Developer ID need a paid developer account; until then `make app` produces an ad-hoc signed build for local use.
