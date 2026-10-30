import AppKit
import SViewCore

/// Maps an `NSEvent` key press to the keymap's `Key`: printed characters
/// keep their case (so shift is implied), named keys keep modifiers.
enum KeyTranslator {
    private static let named: [UInt16: String] = [
        49: "space",
        36: "enter",
        76: "enter",
        48: "tab",
        53: "esc",
        51: "backspace",
        117: "delete",
        123: "left",
        124: "right",
        125: "down",
        126: "up",
        115: "home",
        119: "end",
        116: "pageup",
        121: "pagedown",
        122: "f1",
        120: "f2",
        99: "f3",
        118: "f4",
        96: "f5",
        97: "f6",
        98: "f7",
        100: "f8",
        101: "f9",
        109: "f10",
        103: "f11",
        111: "f12",
    ]

    /// A key-down event for `key`, used by the SVIEW_KEYS test hook.
    static func event(for key: Key, in window: NSWindow) -> NSEvent? {
        let name = key.base.count == 1 ? (key.base == " " ? "space" : nil) : key.base
        let code = name.flatMap { wanted in named.first { $0.value == wanted }?.key } ?? 0
        var flags: NSEvent.ModifierFlags = []
        if key.modifiers.contains(.command) {
            flags.insert(.command)
        }
        if key.modifiers.contains(.control) {
            flags.insert(.control)
        }
        if key.modifiers.contains(.option) {
            flags.insert(.option)
        }
        if key.modifiers.contains(.shift) || key.base.first?.isUppercase == true {
            flags.insert(.shift)
        }
        let controlCharacters = [
            "enter": "\r",
            "tab": "\t",
            "esc": "\u{1b}",
            "backspace": "\u{7f}",
            "up": "\u{F700}",
            "down": "\u{F701}",
            "left": "\u{F702}",
            "right": "\u{F703}",
        ]
        let characters = key.base.count == 1 ? key.base : (controlCharacters[key.base] ?? "")
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters.lowercased(),
            isARepeat: false,
            keyCode: code
        )
    }

    static func key(for event: NSEvent) -> Key? {
        var modifiers: Key.Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if let name = named[event.keyCode] {
            return Key(name, modifiers: modifiers)
        }
        // With control or command, use the unmodified character (ctrl-n is
        // "n", not a control code); otherwise the printed one, so option
        // combinations that print a character bind as that character.
        let source = modifiers.isDisjoint(with: [.control, .command])
            ? event.characters
            : event.charactersIgnoringModifiers
        guard let text = source, text.count == 1, let character = text.first, !character.isNewline else {
            return nil
        }
        if modifiers.isDisjoint(with: [.control, .command]) {
            modifiers.remove(.option)
        }
        return Key(String(character), modifiers: modifiers)
    }
}
