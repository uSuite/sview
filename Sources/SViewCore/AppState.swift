import Foundation

/// Disposable session state in `~/.config/sview/state.json` (SV-209):
/// recent folders, most recent first, and the last file viewed. Never hand
/// edited; a missing or broken file is simply an empty state.
public struct AppState: Codable, Sendable, Equatable {
    public static let recentLimit = 20

    public private(set) var recentFolders: [String] = []
    public private(set) var lastFile: String?

    public init() {}

    /// Records `file` as viewed: its folder moves to the front of the list.
    public mutating func noteViewed(_ file: URL) {
        lastFile = file.path
        let folder = file.deletingLastPathComponent().path
        recentFolders.removeAll { $0 == folder }
        recentFolders.insert(folder, at: 0)
        if recentFolders.count > Self.recentLimit {
            recentFolders.removeLast(recentFolders.count - Self.recentLimit)
        }
    }

    public mutating func clearRecents() {
        recentFolders.removeAll()
    }

    /// Recent folders that still exist.
    public var existingRecentFolders: [URL] {
        recentFolders
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func load(from url: URL) -> AppState {
        guard let data = try? Data(contentsOf: url),
            let state = try? JSONDecoder().decode(AppState.self, from: data)
        else {
            return AppState()
        }
        return state
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
