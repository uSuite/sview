# sView

macOS-native, keyboard-first image viewer (qView spirit, vim keys). Swift 6, SwiftUI shell + AppKit canvas, zero dependencies. Read docs/02-tech-stack.md for the architecture and docs/01-backlog.md for the work items (SV-xxx). docs/DECISIONS.md is the source of truth for decisions; docs/local/STATUS.md (untracked) says where we are, and docs/local/03-plan-claude-code.md (untracked) is the phase plan.

## Commands

- `make gen`    regenerate sView.xcodeproj from project.yml (XcodeGen)
- `make test`   scommon's tests when `../scommon` is checked out, then swift test on SViewCore
- `make app`    xcodebuild Debug sView.app into build/
- `make run`    build and launch with fixtures/sample/
- `make smoke`  scripted UI smoke test with screenshots in build/smoke/
- `make bench`  loading benchmarks, append to bench/RESULTS.md

## Layers

Shared (the scommon package, the sibling ../scommon when present, else `uSuite/scommon` from GitHub; re-exported by SViewCore) -> Core (Sources/SViewCore, pure Swift, strict concurrency, fully unit tested) -> UI (Sources/sView, NSView canvas + SwiftUI overlays) -> App (menus, UTIs, launcher). Dependencies point down only. Every user action is a `Command` case; keys, menus and `:` all dispatch Commands.

## Rules

- Plan, get approval, then implement. PoC in scratch/ when unsure.
- One logical change per commit; the message says why. Default git identity, no trailers.
- make test before every commit; make app before UI commits. Never commit red.
- No third-party packages without a DECISIONS.md entry.
- Shared code changes in ../scommon first, test first, with a tag per change set (patch for a fix, minor for a new key or type); it is good once this app's smoke passes against it. Raise the `from:` minimum in Package.swift when this app needs a newer tag; never edit scommon's files through this checkout.
- Multi-line calls: one argument per line. No banner comment lines.
- Plain text, no em-dash character, no horizontal rules in markdown, one paragraph per line.
- Config files are plain `key value` text; the parser is ours.
- git-flow: branch feature/<name> off develop, merge back with --no-ff; master only via release/X.Y.Z, tagged vX.Y.Z. Semver lives in VERSION.
- Update docs/local/STATUS.md at the end of every session.
