import Foundation

/// Narrows the sequence by file name (SV-305).
///
/// Smart case: a pattern with an upper-case letter is case-sensitive. A
/// pattern with regex metacharacters is a regular expression when it
/// compiles, otherwise everything is a plain substring match.
public struct Filter: Sendable, Equatable {
    public let pattern: String
    public let isRegex: Bool
    private let caseSensitive: Bool

    private static let metacharacters = CharacterSet(charactersIn: "\\^$.*+?()[]{}|")

    public init(_ pattern: String) {
        self.pattern = pattern
        caseSensitive = pattern.contains { $0.isUppercase }
        let looksLikeRegex = pattern.rangeOfCharacter(from: Self.metacharacters) != nil
        isRegex = looksLikeRegex && (try? NSRegularExpression(pattern: pattern)) != nil
    }

    public var isEmpty: Bool { pattern.isEmpty }

    public func matches(_ name: String) -> Bool {
        if pattern.isEmpty {
            return true
        }
        var options: String.CompareOptions = isRegex ? [.regularExpression] : []
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }
        return name.range(of: pattern, options: options) != nil
    }

    public func apply(to items: [ImageItem]) -> [ImageItem] {
        pattern.isEmpty ? items : items.filter { matches($0.name) }
    }
}
