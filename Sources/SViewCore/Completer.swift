import Foundation

/// Tab completion for the `:` line (SV-304): command names, `:set` options
/// and values, `:sort` keys, `:map` commands and `:cd` directories.
/// Candidates are whole lines, so the prompt can replace its text with one.
public enum Completer {
    static let values: [String: [String]] = [
        "wrap": ["true", "false"],
        "recursive": ["true", "false"],
        "skip_empty_folders": ["true", "false"],
        "click_navigates": ["true", "false"],
        "show_title": ["true", "false"],
        "size_window_to_image": ["true", "false"],
        "restore_session": ["true", "false"],
        "zoom": Config.ZoomMode.allCases.map(\.rawValue),
        "wheel": Config.Wheel.allCases.map(\.rawValue),
        "background": ["auto", "checker", "black", "white", "grey"],
        "sort": SortKey.allCases.map(\.rawValue),
    ]

    public static func complete(
        _ line: String,
        folder: URL?,
        hooks: [String] = []
    ) -> [String] {
        let words = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let first = words.first else {
            return []
        }
        if words.count == 1 {
            let names = Set(Command.names + Command.aliases.keys)
            return names.filter { $0.hasPrefix(first) }.sorted()
        }
        let head = words.dropLast().joined(separator: " ") + " "
        let partial = words.last ?? ""
        let options: [String]
        switch (first, words.count) {
        case ("set", 2):
            options = Config.keys
        case ("set", 3):
            options = values[words[1]] ?? []
        case ("sort", 2):
            options = SortKey.allCases.map(\.rawValue)
        case ("sort", 3):
            options = ["asc", "desc"]
        case ("map", 3):
            options = Command.names
        case ("run", 2):
            options = hooks
        case ("cd", _):
            let path = words.dropFirst().joined(separator: " ")
            return directories(matching: path, from: folder).map { "cd " + $0 }
        default:
            options = []
        }
        return options.filter { $0.hasPrefix(partial) }.sorted().map { head + $0 }
    }

    /// Sub-folders completing `path` (absolute, `~`, or relative to `folder`),
    /// written the way the user started typing, each ending in `/`.
    static func directories(
        matching path: String,
        from folder: URL?
    ) -> [String] {
        let slash = path.lastIndex(of: "/")
        let typedDirectory = slash.map { String(path[...$0]) } ?? ""
        let prefix = slash.map { String(path[path.index(after: $0)...]) } ?? path
        let base = typedDirectory.isEmpty
            ? (folder ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            : Dispatcher.resolve(typedDirectory, from: folder)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }
        return children
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix(prefix) && ($0.hasPrefix(".") == prefix.hasPrefix(".")) }
            .sorted(by: Sorter.naturalLess)
            .map { typedDirectory + $0 + "/" }
    }

    /// The longest prefix all candidates share.
    public static func commonPrefix(_ candidates: [String]) -> String {
        guard var prefix = candidates.first else {
            return ""
        }
        for candidate in candidates.dropFirst() {
            while !candidate.hasPrefix(prefix) {
                prefix.removeLast()
            }
        }
        return prefix
    }
}
