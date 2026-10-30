/// Position within a sequence of `count` items (SV-201, SV-302).
///
/// Pure index arithmetic: moves clamp at the ends unless `wraps` is set, and
/// an empty sequence has no position. Counts come from vim-style prefixes.
public struct Navigator: Sendable, Equatable {
    public private(set) var count: Int
    public private(set) var index: Int?
    public var wraps: Bool

    public init(
        count: Int,
        index: Int = 0,
        wraps: Bool = false
    ) {
        self.count = max(0, count)
        self.wraps = wraps
        self.index = self.count == 0 ? nil : min(max(0, index), self.count - 1)
    }

    /// One-based position for display, `nil` when empty.
    public var position: Int? { index.map { $0 + 1 } }
    public var isAtFirst: Bool { index == 0 }
    public var isAtLast: Bool { index == count - 1 }

    @discardableResult
    public mutating func move(by offset: Int) -> Bool {
        guard let current = index else {
            return false
        }
        var target = current + offset
        if wraps {
            target = ((target % count) + count) % count
        } else {
            target = min(max(0, target), count - 1)
        }
        index = target
        return target != current
    }

    @discardableResult
    public mutating func first() -> Bool { jump(to: 0) }

    @discardableResult
    public mutating func last() -> Bool { jump(to: count - 1) }

    /// Goes to the one-based position `n`, clamped into range.
    @discardableResult
    public mutating func go(to n: Int) -> Bool { jump(to: n - 1) }

    @discardableResult
    public mutating func jump(to target: Int) -> Bool {
        guard count > 0 else {
            return false
        }
        let clamped = min(max(0, target), count - 1)
        defer { index = clamped }
        return clamped != index
    }

    /// Changes the sequence length, keeping `index` (or the nearest valid one).
    public mutating func reset(
        count newCount: Int,
        index newIndex: Int?
    ) {
        count = max(0, newCount)
        if count == 0 {
            index = nil
        } else {
            index = min(max(0, newIndex ?? 0), count - 1)
        }
    }
}
