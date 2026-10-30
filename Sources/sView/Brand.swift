import AppKit

/// sView's colours from docs/04-branding.md: the icon is deep blue, and a
/// lower-saturation variant of it is the accent inside the app, so the icon
/// and the UI agree.
enum Brand {
    /// Selection, the current thumbnail and memo highlights.
    static let accent = NSColor(srgbRed: 0x45 / 255.0, green: 0x73 / 255.0, blue: 0xdb / 255.0, alpha: 1)
}
