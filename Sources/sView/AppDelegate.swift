import AppKit
import SViewCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [ViewerWindowController] = []
    private var launched = false
    private var openedDuringLaunch = false
    private var configWatcher: DirectoryWatcher?
    private var compares: [CompareWindowController] = []
    private var settingsWindow: SettingsWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launched = true
        // Config and keymap edits, :set and :map apply at once (SV-503).
        configWatcher = DirectoryWatcher(
            url: AppModel.shared.paths.directory,
            files: ["config", "keymap"]
        ) { [weak self] in
            MainActor.assumeIsolated {
                self?.reloadSettings()
            }
        }
        // Paths given on the command line arrive as open events when AppKit
        // recognises them; anything it did not deliver is opened here.
        if !openedDuringLaunch {
            let paths = Self.pathArguments(CommandLine.arguments)
            if paths.isEmpty {
                newWindow(opening: Self.restoredFile())
            } else {
                paths.forEach { newWindow(opening: $0) }
            }
        }
        NSApp.activate()
        // `SVIEW_SETTINGS=1` opens Settings after launch, for smoke.
        if ProcessInfo.processInfo.environment["SVIEW_SETTINGS"] != nil {
            showSettings(nil)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if !launched {
            openedDuringLaunch = true
        }
        for url in urls {
            if let empty = controllers.first(where: { $0.isEmpty }) {
                empty.open(url)
            } else {
                newWindow(opening: url)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        reloadSettings()
    }

    /// Applies changed config and keymap files to the menu and every window,
    /// and reports the first problem in them.
    private func reloadSettings() {
        guard AppModel.shared.reloadIfChanged() else {
            return
        }
        NSApp.mainMenu = MainMenu.build()
        controllers.forEach { $0.settingsChanged() }
        settingsWindow?.model.refresh()
        let issues = AppModel.shared.issues
        DebugLog.log("settings reloaded, \(issues.count) issues")
        if let first = issues.first {
            let more = issues.count > 1 ? " (+\(issues.count - 1) more)" : ""
            controllers.first { $0.window?.isKeyWindow == true }?.showToast(first + more)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @discardableResult
    func newWindow(opening url: URL?) -> ViewerWindowController {
        let controller = ViewerWindowController()
        controller.onClose = { [weak self, weak controller] in
            self?.controllers.removeAll { $0 === controller }
        }
        controllers.append(controller)
        controller.showWindow(nil)
        if let url {
            controller.open(url)
        }
        return controller
    }

    /// A side by side compare window for two images (SV-604).
    func compare(_ left: URL, _ right: URL) {
        DebugLog.log("compare \(left.lastPathComponent) \(right.lastPathComponent)")
        let controller = CompareWindowController(left, right)
        controller.onClose = { [weak self, weak controller] in
            self?.compares.removeAll { $0 === controller }
        }
        compares.append(controller)
        controller.showWindow(nil)
    }

    /// The last file viewed, when `restore_session` is on and it still exists.
    static func restoredFile() -> URL? {
        guard AppModel.shared.config.restoreSession,
            let path = AppModel.shared.appState.lastFile,
            FileManager.default.fileExists(atPath: path)
        else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    /// Existing file or folder paths among the arguments, skipping AppKit's
    /// `-Key value` defaults pairs.
    static func pathArguments(_ arguments: [String]) -> [URL] {
        var urls: [URL] = []
        var skipNext = false
        for argument in arguments.dropFirst() {
            if skipNext {
                skipNext = false
                continue
            }
            if argument.hasPrefix("-") {
                skipNext = argument.count > 1
                continue
            }
            let url = URL(fileURLWithPath: (argument as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            }
        }
        return urls
    }

    // MARK: Menu actions

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .folder]
        guard panel.runModal() == .OK else {
            return
        }
        application(NSApp, open: panel.urls)
    }

    @objc func newViewerWindow(_ sender: Any?) {
        newWindow(opening: nil)
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else {
            return
        }
        application(NSApp, open: [url])
    }

    @objc func clearRecents(_ sender: Any?) {
        AppModel.shared.clearRecents()
    }

    /// About box (SV-501): version and build from the bundle, licence and
    /// where the plain-text settings live.
    @objc func showAbout(_ sender: Any?) {
        let credits = NSAttributedString(
            string: "Keyboard-first image viewer.\nMIT licence. Settings in ~/.config/sview/.\nPress ? in a window for the keys.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }

    /// sView > Settings… (SV-511), one window for the app; what it writes
    /// applies at once.
    @objc func showSettings(_ sender: Any?) {
        let controller = settingsWindow ?? SettingsWindowController()
        controller.model.onWrite = { [weak self] in
            self?.reloadSettings()
        }
        settingsWindow = controller
        controller.show()
    }

    /// Settings are plain files (SV-503); this shows them in Finder.
    @objc func openConfigFolder(_ sender: Any?) {
        NSWorkspace.shared.open(AppModel.shared.paths.directory)
    }
}
