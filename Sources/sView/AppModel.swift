import AppKit
import SViewCore

/// App-wide settings shared by every window: the config, the keymap, and
/// their issues. Reloaded when the files change on disk.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let paths = ConfigPaths()
    private(set) var config = Config()
    private(set) var keymap = Keymap.default
    private(set) var issues: [String] = []
    private var stamps: [URL: Date] = [:]

    /// Recents and the last file viewed (SV-209), saved shortly after changes.
    private(set) var appState = AppState()
    private var saveTask: Task<Void, Never>?

    /// One decode cache for all windows, sized by `cache_mb`.
    let pipeline: ImagePipeline

    private init() {
        try? paths.ensureDefaults(keymap: Keymap.defaultText)
        pipeline = ImagePipeline(budgetBytes: 512 * 1024 * 1024)
        pipeline.displaySpace = NSScreen.main?.colorSpace?.cgColorSpace
        appState = AppState.load(from: paths.state)
        reload()
    }

    func noteViewed(_ file: URL) {
        guard appState.lastFile != file.path else {
            return
        }
        appState.noteViewed(file)
        scheduleSave()
    }

    func clearRecents() {
        appState.clearRecents()
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let state = appState
        let url = paths.state
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }
            try? state.save(to: url)
        }
    }

    /// Re-reads config and keymap when either file changed since the last
    /// read; returns whether anything was reloaded (SV-503 hot reload).
    @discardableResult
    func reloadIfChanged() -> Bool {
        let changed = [paths.config, paths.keymap].contains { stamp($0) != stamps[$0] }
        if changed {
            reload()
        }
        return changed
    }

    private func reload() {
        let (config, configIssues) = paths.loadConfig()
        self.config = config
        let shared = self.pipeline
        Task {
            await shared.setBudget(config.cacheMB * 1024 * 1024)
        }
        var issues = configIssues.map { "config \($0)" }
        if let text = try? String(contentsOf: paths.keymap, encoding: .utf8) {
            let (keymap, keymapIssues) = Keymap.overlaid(text)
            self.keymap = keymap
            issues += keymapIssues.map { "keymap \($0)" }
        } else {
            keymap = Keymap.default
        }
        self.issues = issues
        for url in [paths.config, paths.keymap] {
            stamps[url] = stamp(url)
        }
    }

    private func stamp(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
