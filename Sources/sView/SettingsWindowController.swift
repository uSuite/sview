import AppKit
import SViewCore
import SwiftUI
import UniformTypeIdentifiers

/// What the Settings window shows (SV-511). The config file stays the
/// truth: each control writes its key's line through `ConfigPaths.persist`,
/// as `:set` does, keeping comments and `hook` lines, and the reload that
/// follows applies it to every window and comes back here.
@MainActor
@Observable
final class SettingsModel {
    var config = Config()
    var issues: [String] = []
    /// The last thing an action did, under the buttons that did it.
    var status = ""
    /// Applies a written file at once, without waiting for the folder watch.
    @ObservationIgnored var onWrite: () -> Void = {}

    init() {
        refresh()
    }

    func refresh() {
        config = AppModel.shared.config
        issues = AppModel.shared.issues
    }

    /// Writes `key` when `change` gives it another value.
    func change(
        _ key: String,
        _ change: (inout Config) -> Void
    ) {
        var changed = config
        change(&changed)
        guard let text = changed.text(for: key), text != config.text(for: key) else {
            return
        }
        do {
            try AppModel.shared.paths.persist(key, text)
            status = "\(key) \(text)"
            onWrite()
        } catch {
            status = "\(error)"
        }
        refresh()
    }

    /// A binding to one setting, written as `key` when it changes.
    func binding<Value>(
        _ key: String,
        _ path: WritableKeyPath<Config, Value>
    ) -> Binding<Value> {
        Binding(
            get: { self.config[keyPath: path] },
            set: { value in
                self.change(key) { $0[keyPath: path] = value }
            }
        )
    }
}

/// sView > Settings… (SV-511): one window for the app, the General pane.
@MainActor
final class SettingsWindowController: NSWindowController {
    let model = SettingsModel()

    init() {
        let hosting = NSHostingController(rootView: GeneralSettingsView(model: model))
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Settings"
        window.setFrameAutosaveName("Settings")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func show() {
        model.refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        DebugLog.log("settings shown")
    }
}

/// Import Config… and Export Config…, with the shared `ConfigArchive`.
@MainActor
enum ConfigPanels {
    /// The zip is read and checked first; the files it replaces are named,
    /// with their problems, before anything changes.
    static func importConfig(_ model: SettingsModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.message = "Choose a config zip made by Export Config or :export"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        Task {
            let files: [ConfigArchive.File]
            do {
                files = try await ConfigArchive.sview.inspect(url, check: ConfigArchive.sviewIssues)
            } catch {
                model.status = "\(error)"
                return
            }
            let names = files.map(\.name)
            let alert = NSAlert()
            alert.messageText = "Replace \(names.joined(separator: " and ")) with the ones in \(url.lastPathComponent)?"
            var info = "The current files are kept as \(names.map { $0 + ".bak" }.joined(separator: " and ")) in the config folder."
            for file in files where !file.issues.isEmpty {
                info += "\n\n\(file.name):\n" + file.issues.prefix(5).joined(separator: "\n")
                if file.issues.count > 5 {
                    info += "\n(+\(file.issues.count - 5) more)"
                }
            }
            alert.informativeText = info
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
            do {
                let written = try ConfigArchive.apply(files, to: AppModel.shared.paths.directory)
                model.status = "Imported \(written.joined(separator: " and ")); the old files are kept as .bak"
                model.onWrite()
            } catch {
                model.status = "\(error)"
            }
            model.refresh()
        }
    }

    /// The zip `:export` writes, where the author chooses.
    static func exportConfig(_ model: SettingsModel) {
        let suggested = ConfigArchive.sview.destination(for: "", folder: nil)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.directoryURL = suggested.deletingLastPathComponent()
        panel.nameFieldStringValue = suggested.lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        let paths = AppModel.shared.paths
        Task {
            do {
                let names = try await ConfigArchive.sview.export(from: paths, to: url)
                model.status = "Exported \(names.count) files to \(url.lastPathComponent)"
            } catch {
                model.status = "\(error)"
            }
        }
    }
}
