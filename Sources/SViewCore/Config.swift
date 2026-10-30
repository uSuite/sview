import Foundation
import SCommon

/// Settings from `~/.config/sview/config` (SV-503). Unknown keys and bad
/// values are reported as issues and leave the default in place, so a typo
/// never stops the app from starting.
public struct Config: KeyValueSettings, Equatable {
    public enum Background: Sendable, Equatable {
        case auto
        case checker
        case color(red: Double, green: Double, blue: Double)
    }

    public enum ZoomMode: String, Sendable, CaseIterable {
        case fit
        case width
        case height
        case actual
    }

    public enum Wheel: String, Sendable, CaseIterable {
        case navigate
        case zoom
    }


    public var preload = 2
    public var cacheMB = 512
    public var wrap = false
    public var sort = SortOrder()
    public var recursive = false
    public var skipEmptyFolders = true
    public var background = Background.auto
    public var zoom = ZoomMode.fit
    public var wheel = Wheel.navigate
    public var clickNavigates = false
    public var slideshowSeconds = 3.0
    public var showTitle = true
    public var sizeWindowToImage = false
    public var restoreSession = false
    /// `:run` hooks by name (SV-603), from `hook <name> <command>` lines.
    public var hooks: [String: String] = [:]

    public init() {}

    public static let keys = [
        "preload",
        "cache_mb",
        "wrap",
        "sort",
        "recursive",
        "skip_empty_folders",
        "background",
        "zoom",
        "wheel",
        "click_navigates",
        "slideshow_seconds",
        "show_title",
        "size_window_to_image",
        "restore_session",
    ]

    public enum SetError: Error, Equatable, CustomStringConvertible {
        case unknownKey(String)
        case badValue(key: String, value: String, expected: String)

        public var description: String {
            switch self {
            case .unknownKey(let key):
                return "unknown option '\(key)'"
            case .badValue(let key, let value, let expected):
                return "\(key): '\(value)' is not \(expected)"
            }
        }
    }

    /// Applies one `key value` pair, the same path `:set` uses.
    public mutating func set(_ key: String, _ value: String) throws(SetError) {
        switch key {
        case "preload":
            preload = try Self.int(key, value, range: 0...20)
        case "cache_mb":
            cacheMB = try Self.int(key, value, range: 16...65536)
        case "wrap":
            wrap = try Self.bool(key, value)
        case "sort":
            sort = try Self.sortOrder(key, value)
        case "recursive":
            recursive = try Self.bool(key, value)
        case "skip_empty_folders":
            skipEmptyFolders = try Self.bool(key, value)
        case "background":
            background = try Self.background(key, value)
        case "zoom":
            zoom = try Self.choice(key, value)
        case "wheel":
            wheel = try Self.choice(key, value)
        case "click_navigates":
            clickNavigates = try Self.bool(key, value)
        case "slideshow_seconds":
            guard let seconds = Double(value), seconds >= 0.2, seconds <= 3600 else {
                throw .badValue(key: key, value: value, expected: "a number of seconds from 0.2 to 3600")
            }
            slideshowSeconds = seconds
        case "show_title":
            showTitle = try Self.bool(key, value)
        case "size_window_to_image":
            sizeWindowToImage = try Self.bool(key, value)
        case "restore_session":
            restoreSession = try Self.bool(key, value)
        case "hook":
            let name = String(value.prefix { !$0.isWhitespace })
            let command = value.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !command.isEmpty else {
                throw .badValue(key: key, value: value, expected: "a name and a shell command")
            }
            hooks[name] = command
        default:
            throw .unknownKey(key)
        }
    }

    private static func int(
        _ key: String,
        _ value: String,
        range: ClosedRange<Int>
    ) throws(SetError) -> Int {
        guard let number = Int(value), range.contains(number) else {
            throw .badValue(key: key, value: value, expected: "a whole number from \(range.lowerBound) to \(range.upperBound)")
        }
        return number
    }

    private static func bool(_ key: String, _ value: String) throws(SetError) -> Bool {
        switch value.lowercased() {
        case "true", "yes", "on", "1":
            return true
        case "false", "no", "off", "0":
            return false
        default:
            throw .badValue(key: key, value: value, expected: "true or false")
        }
    }

    private static func choice<T: RawRepresentable & CaseIterable>(
        _ key: String,
        _ value: String
    ) throws(SetError) -> T where T.RawValue == String {
        guard let parsed = T(rawValue: value.lowercased()) else {
            let names = T.allCases.map(\.rawValue).joined(separator: ", ")
            throw .badValue(key: key, value: value, expected: "one of \(names)")
        }
        return parsed
    }

    static func sortOrder(_ key: String, _ value: String) throws(SetError) -> SortOrder {
        let words = value.lowercased().split(separator: " ").map(String.init)
        guard let first = words.first,
            let sortKey = SortKey(rawValue: first),
            words.count <= 2
        else {
            throw .badValue(key: key, value: value, expected: "name, date, size or type, optionally followed by asc or desc")
        }
        switch words.dropFirst().first {
        case nil, "asc":
            return SortOrder(key: sortKey)
        case "desc":
            return SortOrder(key: sortKey, descending: true)
        default:
            throw .badValue(key: key, value: value, expected: "asc or desc after the sort key")
        }
    }

    private static func background(_ key: String, _ value: String) throws(SetError) -> Background {
        switch value.lowercased() {
        case "auto":
            return .auto
        case "checker":
            return .checker
        case "black":
            return .color(red: 0, green: 0, blue: 0)
        case "white":
            return .color(red: 1, green: 1, blue: 1)
        case "grey", "gray":
            return .color(red: 0.5, green: 0.5, blue: 0.5)
        default:
            let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
            guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else {
                throw .badValue(key: key, value: value, expected: "auto, checker, black, white, grey or #rrggbb")
            }
            return .color(
                red: Double((rgb >> 16) & 0xff) / 255,
                green: Double((rgb >> 8) & 0xff) / 255,
                blue: Double(rgb & 0xff) / 255
            )
        }
    }

    /// The value of `key` as the config file writes it, so `set(key, text)`
    /// gives this config's value back (SV-511: the Settings window writes
    /// each control through the same line `:set` writes). `nil` for a key
    /// that is not one of `keys`.
    public func text(for key: String) -> String? {
        switch key {
        case "preload":
            return String(preload)
        case "cache_mb":
            return String(cacheMB)
        case "wrap":
            return String(wrap)
        case "sort":
            return sort.key.rawValue + (sort.descending ? " desc" : "")
        case "recursive":
            return String(recursive)
        case "skip_empty_folders":
            return String(skipEmptyFolders)
        case "background":
            return Self.text(for: background)
        case "zoom":
            return zoom.rawValue
        case "wheel":
            return wheel.rawValue
        case "click_navigates":
            return String(clickNavigates)
        case "slideshow_seconds":
            return slideshowSeconds == slideshowSeconds.rounded() ? String(Int(slideshowSeconds)) : String(slideshowSeconds)
        case "show_title":
            return String(showTitle)
        case "size_window_to_image":
            return String(sizeWindowToImage)
        case "restore_session":
            return String(restoreSession)
        default:
            return nil
        }
    }

    /// `auto`, `checker`, a named grey the parser knows, or `#rrggbb`.
    public static func text(for background: Background) -> String {
        switch background {
        case .auto:
            return "auto"
        case .checker:
            return "checker"
        case .color(let red, let green, let blue):
            func byte(_ value: Double) -> Int {
                Int((min(max(value, 0), 1) * 255).rounded())
            }
            switch (byte(red), byte(green), byte(blue)) {
            case (0, 0, 0):
                return "black"
            case (255, 255, 255):
                return "white"
            case (128, 128, 128):
                return "grey"
            case let (r, g, b):
                return String(format: "#%02x%02x%02x", r, g, b)
            }
        }
    }

    /// Written to `~/.config/sview/config` on first run so the file documents itself.
    public static let defaultText = """
        # sView config. One `key value` per line, # starts a comment.
        # Edit by hand or with :set <key> <value>; the file is reloaded on save.

        # images decoded ahead and behind the current one
        preload 2
        # decoded image cache budget in megabytes
        cache_mb 512
        # next on the last image goes to the first
        wrap false
        # name, date, size or type, optionally followed by asc or desc
        sort name
        # flatten the folder tree into one sequence
        recursive false
        # ] and [ skip sibling folders without images
        skip_empty_folders true
        # auto, checker, black, white, grey or #rrggbb
        background auto
        # zoom on open: fit, width, height or actual
        zoom fit
        # scroll wheel: navigate or zoom
        wheel navigate
        # click the left or right half of the window to go back or forward
        click_navigates false
        slideshow_seconds 3
        # window title shows name, position, size
        show_title true
        # resize the window to the image on open instead of keeping its size
        size_window_to_image false
        # launched with nothing to open, reopen the last image viewed
        restore_session false

        # :run <name> hooks, any number: hook <name> <shell command>
        # $FILE, $FOLDER and $MARKED (one path per line) are set; runs in $FOLDER.
        # hook evidence python3 ../report.py --dry-run

        """
}
