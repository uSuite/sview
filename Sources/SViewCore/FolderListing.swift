import Foundation

/// One row of the folder sidebar.
public struct FolderEntry: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case parent
        case sibling
        case child
    }

    public let url: URL
    public let kind: Kind
    public let imageCount: Int
    public let isCurrent: Bool

    public var name: String {
        kind == .parent ? ".." : url.lastPathComponent
    }
}

/// The rows of the folder sidebar (SV-207): the parent, the siblings of
/// the current folder in natural order, and the current folder's children
/// right under it, each with its image count.
public enum FolderListing {
    @concurrent
    public static func entries(for folder: URL) async -> [FolderEntry] {
        list(folder)
    }

    static func list(_ folder: URL) -> [FolderEntry] {
        var rows: [FolderEntry] = []
        let parent = FolderTree.parent(of: folder)
        if let parent {
            rows.append(FolderEntry(url: parent, kind: .parent, imageCount: count(parent), isCurrent: false))
        }
        let siblings = parent.flatMap { try? FolderScanner.subfolders(of: $0) } ?? [folder]
        for sibling in siblings {
            let isCurrent = sibling.lastPathComponent == folder.lastPathComponent
            rows.append(FolderEntry(url: sibling, kind: .sibling, imageCount: count(sibling), isCurrent: isCurrent))
            if isCurrent {
                for child in (try? FolderScanner.subfolders(of: sibling)) ?? [] {
                    rows.append(FolderEntry(url: child, kind: .child, imageCount: count(child), isCurrent: false))
                }
            }
        }
        return rows
    }

    private static func count(_ folder: URL) -> Int {
        (try? FolderScanner.images(in: folder).count) ?? 0
    }

    /// Rows whose name contains `text`, ignoring case; the parent row and
    /// the current folder always stay so the reader keeps their bearings.
    public static func filter(_ rows: [FolderEntry], by text: String) -> [FolderEntry] {
        guard !text.isEmpty else {
            return rows
        }
        return rows.filter { row in
            row.kind == .parent || row.isCurrent || row.name.range(of: text, options: .caseInsensitive) != nil
        }
    }
}
