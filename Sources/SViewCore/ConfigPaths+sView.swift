import Foundation
import SCommon

/// sView's files live in `~/.config/sview/` (DECISIONS 2026-10-25).
extension ConfigPaths {
    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.init(app: "sview", environment: environment, home: home)
    }

    public func ensureDefaults(keymap keymapText: String) throws {
        try ensureDefaults(config: Config.defaultText, keymap: keymapText)
    }

    public func loadConfig() -> (config: Config, issues: [LineIssue]) {
        load(Config.self)
    }

    public func persist(
        _ key: String,
        _ value: String
    ) throws {
        try persist(key, value, as: Config.self)
    }
}

/// `:export` and the Settings window's Import Config and Export Config
/// (SV-503, SV-511): config and keymap, never state.json, in one `sview/`
/// folder of a zip.
extension ConfigArchive {
    public static let sview = ConfigArchive(
        app: "sview",
        fileNames: ["config", "keymap"]
    )

    /// The problems sView would report in a file a zip brings, as it
    /// reports them for the files on disk.
    @Sendable
    public static func sviewIssues(
        name: String,
        text: String
    ) -> [String] {
        name == "config"
            ? Config.parse(text).issues.map(\.description)
            : Keymap.overlaid(text).issues.map { "\($0)" }
    }
}
