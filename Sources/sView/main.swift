import AppKit

// AppKit lifecycle (DECISIONS 2026-10-25): an explicit delegate receives
// open-document events for Finder, `open -a` and argv paths.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
