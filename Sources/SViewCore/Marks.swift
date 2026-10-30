import Foundation

/// The marked set (SV-306): files picked during a viewing pass to trash,
/// copy, reveal or export together.
public struct Marks: Sendable, Equatable {
    public private(set) var urls: Set<URL> = []

    public init() {}

    /// Plain path form; never consults the file system, so a trashed or
    /// renamed file still matches its mark.
    static func key(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path)
    }

    public var count: Int { urls.count }
    public var isEmpty: Bool { urls.isEmpty }

    public func contains(_ url: URL) -> Bool {
        urls.contains(Self.key(url))
    }

    /// Returns whether `url` is marked afterwards.
    @discardableResult
    public mutating func toggle(_ url: URL) -> Bool {
        let key = Self.key(url)
        if urls.remove(key) == nil {
            urls.insert(key)
            return true
        }
        return false
    }

    public mutating func mark(_ list: [URL]) {
        urls.formUnion(list.map(Self.key))
    }

    public mutating func unmark(_ url: URL) {
        urls.remove(Self.key(url))
    }

    public mutating func clear() {
        urls.removeAll()
    }

    /// Marked items in sequence order.
    public func ordered(in items: [ImageItem]) -> [ImageItem] {
        items.filter { contains($0.url) }
    }

    /// Index of the next marked item after `index` (before it when `offset`
    /// is negative), wrapping around; `nil` when nothing in `items` is marked.
    public func nextIndex(
        from index: Int,
        offset: Int = 1,
        in items: [ImageItem]
    ) -> Int? {
        let marked = items.indices.filter { contains(items[$0].url) }
        guard !marked.isEmpty else {
            return nil
        }
        if offset >= 0 {
            return marked.first { $0 > index } ?? marked.first
        }
        return marked.last { $0 < index } ?? marked.last
    }
}
