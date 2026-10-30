import Foundation

/// Every user-visible action. Keys, menus, the `:` line and tests all speak
/// this vocabulary; each case has a kebab-case name used by the keymap file.
public enum Command: Sendable, Hashable {
    // Sequence
    case next
    case previous
    case first
    case last
    case goTo(Int)
    // h j k l: pan when the image overflows the window, navigate otherwise
    case left
    case right
    case up
    case down
    // View
    case zoomIn
    case zoomOut
    case zoomFit
    case zoomWidth
    case zoomHeight
    case zoomActual
    case rotateLeft
    case rotateRight
    case flipHorizontal
    case flipVertical
    case fullscreen
    case theatre
    case toggleTitle
    case info
    case thumbnails
    case sidebar
    case memo
    case help
    case reload
    case slideshow
    case playPause
    case frameNext
    case framePrevious
    // Folders
    case folderNext
    case folderPrevious
    case folderParent
    case folderEnter
    case recursive
    case sort(SortOrder)
    case reverseSort
    case cd(String)
    // Filter and marks
    case filter(String)
    case filterClear
    case mark
    case markAll
    case markClear
    case markNext
    case markPrevious
    // Files
    case trash
    case trashMarked
    case undo
    case rename(String)
    case copyPath
    case copyName
    case copyImage
    case copyMarked
    case exportMarked(String)
    case reveal
    case revealMarked
    case openWith
    case quickLook
    case newWindow
    case compare
    // Prompts
    case commandLine
    case filterPrompt
    case renamePrompt
    case cancel
    // Config and extension
    case set(key: String, value: String)
    case map(keys: String, command: String)
    /// `:export [path]` (SV-503); an empty path means the Desktop.
    case exportConfig(String)
    case runHook(String)
    case runShell(String)
    case repeatLast
    case quit
    /// Does nothing; mapping keys to it in the keymap file unbinds a default.
    case nop
}

extension Command {
    /// Commands that take no argument, by keymap name.
    public static let simple: [String: Command] = [
        "next": .next,
        "previous": .previous,
        "first": .first,
        "last": .last,
        "left": .left,
        "right": .right,
        "up": .up,
        "down": .down,
        "zoom-in": .zoomIn,
        "zoom-out": .zoomOut,
        "zoom-fit": .zoomFit,
        "zoom-width": .zoomWidth,
        "zoom-height": .zoomHeight,
        "zoom-actual": .zoomActual,
        "rotate-left": .rotateLeft,
        "rotate-right": .rotateRight,
        "flip-horizontal": .flipHorizontal,
        "flip-vertical": .flipVertical,
        "fullscreen": .fullscreen,
        "theatre": .theatre,
        "toggle-title": .toggleTitle,
        "info": .info,
        "thumbnails": .thumbnails,
        "sidebar": .sidebar,
        "memo": .memo,
        "help": .help,
        "reload": .reload,
        "slideshow": .slideshow,
        "play-pause": .playPause,
        "frame-next": .frameNext,
        "frame-previous": .framePrevious,
        "folder-next": .folderNext,
        "folder-previous": .folderPrevious,
        "folder-parent": .folderParent,
        "folder-enter": .folderEnter,
        "recursive": .recursive,
        "reverse-sort": .reverseSort,
        "filter-clear": .filterClear,
        "mark": .mark,
        "mark-all": .markAll,
        "mark-clear": .markClear,
        "mark-next": .markNext,
        "mark-previous": .markPrevious,
        "trash": .trash,
        "trash-marked": .trashMarked,
        "undo": .undo,
        "copy-path": .copyPath,
        "copy-name": .copyName,
        "copy-image": .copyImage,
        "copy-marked": .copyMarked,
        "reveal": .reveal,
        "reveal-marked": .revealMarked,
        "open-with": .openWith,
        "quick-look": .quickLook,
        "new-window": .newWindow,
        "compare": .compare,
        "command-line": .commandLine,
        "filter-prompt": .filterPrompt,
        "rename-prompt": .renamePrompt,
        "cancel": .cancel,
        "repeat": .repeatLast,
        "quit": .quit,
        "nop": .nop,
    ]

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case empty
        case unknown(String)
        case badArgument(command: String, reason: String)

        public var description: String {
            switch self {
            case .empty:
                return "no command"
            case .unknown(let name):
                return "unknown command '\(name)'"
            case .badArgument(let command, let reason):
                return "\(command): \(reason)"
            }
        }
    }

    /// Parses `name [args]` as written in the keymap file.
    public static func parse(_ text: String) throws(ParseError) -> Command {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let name = String(trimmed.prefix { !$0.isWhitespace })
        let rest = trimmed.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            throw .empty
        }
        if let command = simple[name] {
            guard rest.isEmpty else {
                throw .badArgument(command: name, reason: "takes no argument")
            }
            return command
        }
        switch name {
        case "go-to":
            guard let n = Int(rest), n > 0 else {
                throw .badArgument(command: name, reason: "needs a positive image number")
            }
            return .goTo(n)
        case "sort":
            do {
                return .sort(try Config.sortOrder(name, rest))
            } catch {
                throw .badArgument(command: name, reason: "needs name, date, size or type, then optionally asc or desc")
            }
        case "cd":
            return .cd(try required(name, rest, "needs a path"))
        case "filter":
            return .filter(try required(name, rest, "needs a pattern"))
        case "rename":
            return .rename(try required(name, rest, "needs a new name"))
        case "export-marked":
            return .exportMarked(rest)
        case "export-config":
            return .exportConfig(rest)
        case "set":
            let key = String(rest.prefix { !$0.isWhitespace })
            let value = rest.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else {
                throw .badArgument(command: name, reason: "needs an option and a value")
            }
            return .set(key: key, value: value)
        case "map":
            let keys = String(rest.prefix { !$0.isWhitespace })
            let command = rest.dropFirst(keys.count).trimmingCharacters(in: .whitespaces)
            guard !keys.isEmpty, !command.isEmpty else {
                throw .badArgument(command: name, reason: "needs keys and a command")
            }
            return .map(keys: keys, command: command)
        case "run":
            return .runHook(try required(name, rest, "needs a hook name"))
        case "run-shell":
            return .runShell(try required(name, rest, "needs a shell command"))
        default:
            throw .unknown(name)
        }
    }

    private static func required(
        _ name: String,
        _ value: String,
        _ reason: String
    ) throws(ParseError) -> String {
        guard !value.isEmpty else {
            throw .badArgument(command: name, reason: reason)
        }
        return value
    }

    /// Short names accepted on the `:` line on top of the keymap names (SV-304).
    public static let aliases: [String: String] = [
        "q": "quit",
        "quit": "quit",
        "ql": "quick-look",
        "e": "reload",
        "export": "export-config",
        "marked": "export-marked",
    ]

    /// Parses what the user typed after `:`. A bare number is go-to.
    public static func parseCommandLine(_ text: String) throws(ParseError) -> Command {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let n = Int(trimmed) {
            return .goTo(max(1, n))
        }
        let name = String(trimmed.prefix { !$0.isWhitespace })
        if let alias = aliases[name] {
            return try parse(alias + trimmed.dropFirst(name.count))
        }
        return try parse(trimmed)
    }

    private static let simpleNames: [Command: String] = Dictionary(
        uniqueKeysWithValues: simple.map { ($0.value, $0.key) }
    )

    /// Every keymap command name, for completion and help.
    public static let names: [String] = (Array(simple.keys) + [
        "go-to", "sort", "cd", "filter", "rename", "export-marked", "export-config", "set", "map", "run", "run-shell",
    ]).sorted()

    /// The keymap text for this command; `parse(text)` returns it again.
    public var text: String {
        if let name = Self.simpleNames[self] {
            return name
        }
        switch self {
        case .goTo(let n):
            return "go-to \(n)"
        case .sort(let order):
            return "sort \(order.key.rawValue)" + (order.descending ? " desc" : "")
        case .cd(let path):
            return "cd \(path)"
        case .filter(let pattern):
            return "filter \(pattern)"
        case .rename(let name):
            return "rename \(name)"
        case .exportMarked(let path):
            return path.isEmpty ? "export-marked" : "export-marked \(path)"
        case .exportConfig(let path):
            return path.isEmpty ? "export-config" : "export-config \(path)"
        case .set(let key, let value):
            return "set \(key) \(value)"
        case .map(let keys, let command):
            return "map \(keys) \(command)"
        case .runHook(let name):
            return "run \(name)"
        case .runShell(let line):
            return "run-shell \(line)"
        default:
            return "\(self)"
        }
    }

    /// Whether a count prefix changes what the command does.
    public var acceptsCount: Bool {
        switch self {
        case .next, .previous, .left, .right, .up, .down, .first, .last,
            .folderNext, .folderPrevious, .markNext, .markPrevious,
            .zoomIn, .zoomOut, .rotateLeft, .rotateRight, .frameNext, .framePrevious:
            return true
        default:
            return false
        }
    }
}
