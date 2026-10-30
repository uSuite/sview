import CoreGraphics
import Foundation

/// Decoded images under a memory budget with least-recently-used eviction
/// (SV-104). Keyed by file and decode size so a window-size decode and a
/// full decode of the same file can coexist.
public actor ImageCache {
    public struct Key: Sendable, Hashable {
        public let url: URL
        /// Long-edge pixel size requested; 0 means full resolution.
        public let maxPixelSize: Int

        public init(
            url: URL,
            maxPixelSize: Int
        ) {
            self.url = url
            self.maxPixelSize = maxPixelSize
        }
    }

    private struct Entry {
        let image: CGImage
        let cost: Int
        var tick: UInt64
    }

    public private(set) var budget: Int
    public private(set) var totalCost = 0
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0

    public init(budgetBytes: Int) {
        budget = max(0, budgetBytes)
    }

    public var count: Int { entries.count }

    public static func cost(of image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }

    public func image(for key: Key) -> CGImage? {
        guard var entry = entries[key] else {
            return nil
        }
        clock += 1
        entry.tick = clock
        entries[key] = entry
        return entry.image
    }

    /// The largest cached decode of `url` that is at least `minPixelSize`
    /// on the long edge, so a full decode can stand in for a smaller one.
    public func best(for url: URL, minPixelSize: Int) -> CGImage? {
        let candidates = entries.filter { $0.key.url == url }
            .filter { max($0.value.image.width, $0.value.image.height) >= minPixelSize || $0.key.maxPixelSize == 0 }
        guard let key = candidates.min(by: { lhs, rhs in
            max(lhs.value.image.width, lhs.value.image.height) < max(rhs.value.image.width, rhs.value.image.height)
        })?.key else {
            return nil
        }
        return image(for: key)
    }

    public func insert(_ image: CGImage, for key: Key) {
        let cost = Self.cost(of: image)
        if let old = entries.removeValue(forKey: key) {
            totalCost -= old.cost
        }
        guard cost <= budget else {
            return
        }
        clock += 1
        entries[key] = Entry(image: image, cost: cost, tick: clock)
        totalCost += cost
        evict()
    }

    public func contains(_ key: Key) -> Bool {
        entries[key] != nil
    }

    /// Drops every decode of `url`, for a file changed or deleted on disk.
    public func remove(url: URL) {
        for key in entries.keys where key.url == url {
            totalCost -= entries.removeValue(forKey: key)?.cost ?? 0
        }
    }

    public func removeAll() {
        entries.removeAll()
        totalCost = 0
    }

    public func setBudget(_ bytes: Int) {
        budget = max(0, bytes)
        evict()
    }

    private func evict() {
        while totalCost > budget, let oldest = entries.min(by: { $0.value.tick < $1.value.tick }) {
            totalCost -= oldest.value.cost
            entries.removeValue(forKey: oldest.key)
        }
    }
}

/// Which neighbours to decode ahead (SV-104): nearest first, alternating
/// forward and back, forward first since that is the usual direction.
public enum PreloadPlan {
    public static func indices(
        around index: Int,
        count: Int,
        radius: Int,
        wraps: Bool
    ) -> [Int] {
        guard count > 1, radius > 0, (0..<count).contains(index) else {
            return []
        }
        var result: [Int] = []
        for distance in 1...radius {
            for candidate in [index + distance, index - distance] {
                let resolved = wraps ? ((candidate % count) + count) % count : candidate
                if (0..<count).contains(resolved), resolved != index, !result.contains(resolved) {
                    result.append(resolved)
                }
            }
        }
        return result
    }
}
