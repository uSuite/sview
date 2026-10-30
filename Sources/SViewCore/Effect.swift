import Foundation

/// Work a command asks for that is not a pure state change. `Session`
/// performs the file-system ones; the rest go to the UI layer.
public enum Effect: Sendable, Equatable {
    public enum Prompt: Sendable, Equatable {
        case command
        case filter
        case rename
    }

    // Performed by Session
    case openFolder(URL, selecting: URL?)
    case siblingFolder(Int)
    case parentFolder
    case enterFolder
    case rescan
    case trash([URL])
    case undoTrash
    case rename(URL, to: String)
    case persistSetting(key: String, value: String)
    case appendKeymap(String)
    // Performed by the UI
    case pan(dx: Int, dy: Int)
    case prompt(Prompt, text: String)
    case copyText(String)
    case copyImage(URL)
    case reveal([URL])
    case openWith(URL)
    case quickLook(URL)
    case newWindow(URL?)
    case compare(URL, URL)
    case toggleFullscreen
    case playPause
    case frameStep(Int)
    case runShell(String)
    case runHook(String)
    case exportConfig(path: String)
    case exportMarked(path: String, names: [String])
    case quit

    /// Whether `Session` handles this effect itself.
    public var isSessionEffect: Bool {
        switch self {
        case .openFolder, .siblingFolder, .parentFolder, .enterFolder, .rescan,
            .trash, .undoTrash, .rename, .persistSetting, .appendKeymap:
            return true
        default:
            return false
        }
    }
}
