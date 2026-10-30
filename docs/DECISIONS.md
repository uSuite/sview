# sView: decisions

Single source of truth for choices that shape the code. Newest at the bottom. Each entry: date, decision, why, what it rules out. Change a decision by adding a new entry that supersedes the old one, never by editing history.

## 2026-10-25 Stack: Swift, SwiftUI shell, AppKit canvas, Apple frameworks only

Why: the fast decoders on macOS are Apple's (ImageIO, Core Image), native menus, UTIs and dark mode come free, compile times are seconds and the app ships without a runtime. Rules out: Rust (no native decoders or widgets without bindings, heavy toolchain), Qt (the problem being solved), web views. Pure AppKit without SwiftUI stays the fallback. Details in `02-tech-stack.md`.

## 2026-10-25 Minimum macOS 26 Tahoe

Why: Sam's machines run 26; one toolchain (Xcode 26, Swift 6.2), no `#available` branches, JPEG XL, Observation and `onKeyPress` all present. Apple skipped 16 to 25, so 26 is the first major after 15 Sequoia. Rules out: Sequoia and older. Revisit only if an older machine must run it.

## 2026-10-25 Config in `~/.config/sview/`, Linux style, lower-case paths

Why: one directory that can be copied, archived or kept in a dotfiles repo; `$XDG_CONFIG_HOME` honoured; nothing in `~/Library/Application Support`. Files: `config`, `keymap` (hand-edited, plain `key value` text), `state.json` (disposable). Rules out: a Mac-conventional fallback path, UserDefaults for anything the user might want to carry to another machine.

## 2026-10-25 No third-party packages in v1

Why: small owned code over dependencies; the only parsing needed is a `key value` file. A dependency needs an entry here before `Package.swift` changes. The one exception is `scommon`, below, which is ours.

## 2026-10-25 Shared code with sNotate and sCapture becomes the `scommon` package

Why: three siblings (sView, sNotate, sCapture) need folder scanning, natural sort, `poc-` parsing, the `key value` config parser, the keymap grammar and the `~/.config/<app>/` logic. sView writes them first with tests in Phase 1; after Phase 2 is reviewed they move to the SPM package `scommon`, a sibling repository and sView depends on it by local path (`../scommon`). Until then they live in `SViewCore`.

## 2026-10-25 Git-flow branching and semver versioning

Why: Sam asked for git-flow and semver. `master` holds released code only and is tagged `vX.Y.Z`; `develop` is the integration branch; each backlog slice is a `feature/<name>` branch merged into `develop` with `--no-ff` so the feature stays visible in history; releases go through `release/X.Y.Z` and fixes on a release through `hotfix/X.Y.Z`. The version lives in the `VERSION` file (single source), passed to the bundle as `CFBundleShortVersionString`; the build number is the commit count. Rules out: committing features directly on `develop` or `master`, versions hard-coded in `project.yml` or `Info.plist`.

## 2026-10-25 SPM builds the app too; XcodeGen stays the primary app build

Why: the Xcode licence or XcodeGen may be missing on a machine (it was on the first session), and the Command Line Tools can still compile SwiftUI and AppKit. `Package.swift` therefore has an `sView` executable target over the same `Sources/sView` the XcodeGen project uses, and `scripts/bundle.sh` wraps it into an ad-hoc signed `build/sView.app`. `make app` picks Xcode when both Xcode and XcodeGen work, the bundle script otherwise. Rules out: UI code that only builds inside Xcode (asset catalogs compiled by actool, storyboards); resources stay plain files until Phase 6 adds the icon.

## 2026-10-25 Default keymap: `-` zooms out, parent folder is `backspace` and `gu`

Why: the backlog binds `-` to both zoom out (SV-301, P0) and parent folder (SV-303, P1), and the alternative `..` would make `.` (repeat) wait for a second key. Zoom keeps `-`; parent folder gets `backspace` and `gu` ("go up"). Keys are characters whose case carries shift (`G`, not `shift-g`) or named keys with `cmd- ctrl- alt- shift-` modifiers; a binding that is also the prefix of a longer one waits for the next key or a timeout, as in vim. Rules out: `..` and `-` for the parent folder in the shipped keymap (users can still `:map` them).

## 2026-10-25 AppKit app lifecycle; SwiftUI only for overlays

Supersedes the "SwiftUI shell" part of the stack entry. Why: SwiftUI's `WindowGroup` dropped its default window when the app was launched with a path argument, and sView needs open-document events (Finder, `open -a`, argv, `sview`), one `Session` per window and the canvas as first responder, all of which are direct in AppKit. `main.swift` installs an `NSApplicationDelegate`; each window is an `NSWindowController`; the menu bar is built from the command table in code. SwiftUI stays for the non-interactive overlays (toast, info, help) hosted in `NSHostingView`. This is the fallback `02-tech-stack.md` already names. Rules out: SwiftUI `App`, `WindowGroup` and `Commands`.

## 2026-10-25 The keymap file overlays the built-in defaults

Supersedes the keymap part of "Config in ~/.config/sview/": the shipped keymap is still written to `~/.config/sview/keymap` on first run as documentation, but at load time the file is applied over the built-in defaults instead of replacing them. Why: a file copied at first run froze the bindings of that version, so keys added later (for example `C compare`) never reached existing users. A line in the file replaces the default with the same keys; `<keys> nop` removes a default. Rules out: a keymap that only contains what the file lists.

## 2026-10-25 The s means super-fast and swift; never expanded in the product

Why: the apps are fast and built with Swift, and the pun is the brand; spelling out "Swift" would borrow Apple's trademark. Names are `sView`, `sNotate`, `sCapture`; the Swift bird, wordmark and orange are never used. One shared lower-case s mark drawn as a path, three background colours (blue, amber, green), one small accent per app, produced as SVG layers plus an Icon Composer `.icon`. Details in `04-branding.md`, which moves to `scommon/brand/` when that repo exists.

## 2026-10-26 Shared code lives in an `SCommon` target until `scommon` exists

Refines the `scommon` entry. Why: sNotate's Phase 0 was to copy five files, but `Keymap` parsed into sView's `Command` and `ConfigPaths` and `Config` were sView's, so the copies would not have compiled there. The shared code is now its own target in this package, `Sources/SCommon` with `Tests/SCommonTests`, which `SViewCore` depends on and re-exports: `ImageItem`, `Sorter` (`SortKey`, `SortOrder`), `FolderScanner`, `FolderTree`, `FolderModel`, `PocCase`, `KeyValueParser`, `LineIssue`, `Key`, the generic `Keymap<C>`, `KeyMatcher<C>` and `Invocation<C>` over any `KeymapCommand`, `ConfigPaths(app:)` with the `KeyValueSettings` protocol, and the two folder watchers. sView keeps its own types as aliases and extensions, so no app code changed. sNotate Phase 0 copies the two folders whole; the extraction moves them to the sibling `scommon` repository and swaps the target for the package dependency. `nop` is now part of the shared keymap grammar. Rules out: copying individual files between the s-apps, and app types (`Command`, `Config`) inside `SCommon`.

## 2026-10-27 Shared code comes from the `scommon` package by local path (supersedes "Shared code lives in an `SCommon` target until `scommon` exists")

Why: sView and sNotate held byte-identical copies of the same 15 files, and sCapture is next; one copy in the sibling `scommon` repository (0.1.0, extracted from 24ffd9d) replaces the target. `Package.swift` says `.package(path: "../scommon")` and `SViewCore` depends on its `SCommon` product, still re-exporting it with the `SortOrder` alias, so no code above the core changed. `project.yml` needs no entry: Xcode resolves the path dependency through the local package. `make test` runs scommon's tests first, since `swift test` skips a dependency's; `make coverage` reports SViewCore only. Shared code changes in scommon first, test first, tagged per change set, and good once every consumer's smoke passes; no version pin while one person edits all repositories; never edit scommon's files through this checkout. Rules out: a copy of shared code in this repository, and version requirements in the manifest.

## 2026-10-30 Settings window (supersedes "no settings window in v1" in SV-503)

SV-511. sView > Settings… (`cmd-,`, taken from Open Config Folder, since every Mac app opens its settings there) is one window with the General pane, a SwiftUI form: zoom on open, background (auto, checker, black, white, grey or a colour of one's own), scroll wheel, click navigates, sort key and descending, wrap, recursive, skip empty folders, show title, size the window to the image, restore session, slideshow seconds, preload and the cache size; then Import Config…, Export Config…, Open Config Folder and the problems in the files. The config file stays the truth: each control writes its key's line through `ConfigPaths.persist`, the path `:set` takes, with the text `Config.text(for:)` gives (tested to read back to the same value for every key), so comments and `hook` lines are kept, and the reload applies it to every window at once. The zip is scommon's `ConfigArchive` (0.2.0), which replaces this app's `ConfigExport` with the same archive and adds import: the zip's `config` and `keymap` are read and checked as sView reports problems on disk before anything changes, the alert names the files and their problems, and each replaced file is kept as `<name>.bak`; state.json is never touched. Rules out: hooks or keys in the window (they stay in the text files), merging an imported config.

## 2026-10-30 scommon from the sibling checkout, else from GitHub (supersedes "no version pin" in the scommon switch)

Why: sView goes public as `uSuite/sview`, and a clone on its own has no `../scommon`. `Package.swift` uses `.package(path: "../scommon")` when that folder holds a `Package.swift`, and `.package(url: "https://github.com/uSuite/scommon.git", from: "0.3.0")` otherwise; `make test` runs scommon's tests only when the sibling is there. The minimum is raised when this app needs a newer scommon tag. Rules out: a manifest that only builds next to a sibling, `swift package edit` (xcodebuild ignores it).

## 2026-10-30 Published under the uSuite organization

Why: the s-family is open source. The bundle id is `io.github.usuite.sview`, the cask defaults to `uSuite/sview`, fixtures and docs name no employer product or private path, and the hook example is a neutral `../report.py`. The public repository starts from one commit of the released tree; the history before it stays in the private archive copy. docs/STATUS.md and docs/03-plan-claude-code.md are working files of one machine and move to docs/local/, which is ignored. Rules out: publishing the private history, tracking the session log.

## 2026-10-30 The family note moved to scommon

Why: docs/04-branding.md said it lives here until scommon exists. It is now scommon's `brand/README.md`, with the marks of the organization, scommon and sWalk added; this file is a pointer. sView's icon and its layers in `brand/` are unchanged.

## 2026-10-30 Downloads are ad hoc signed zips on GitHub Releases until there is a Developer ID

Why: people should be able to try sView without Xcode, and notarisation needs a paid Apple Developer ID, which the project does not have. `make release` builds the universal app and zip signed ad hoc, and the zip is attached to the GitHub release of the tag with its SHA-256. A downloaded copy carries the quarantine flag, so Gatekeeper blocks its first open; the README says so and gives both ways to allow it (Privacy & Security > Open Anyway, or `xattr -dr com.apple.quarantine`). A local build carries no quarantine flag and is never blocked. Rules out: telling people to turn Gatekeeper off, signing with an Apple Development certificate (it does not pass Gatekeeper either). Revisit with `make notarize` once a Developer ID exists.
