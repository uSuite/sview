import AppKit
import SViewCore

/// The `?` key list (SV-301, SV-310). It owns input while it shows, like the
/// sidebar: the wheel and trackpad scroll it, j k or arrows move a row,
/// ctrl-d ctrl-u half a page, space and shift-space a page, gg and G go to
/// the top and bottom, and ?, q or esc close it. Rows come from the live
/// keymap, laid out in as many columns as the width allows.
final class HelpPaneView: NSView {
    private static let rowHeight: CGFloat = 19
    private static let headerHeight: CGFloat = 40
    private static let columnWidth: CGFloat = 270
    private static let keysWidth: CGFloat = 110
    private static let padding: CGFloat = 16

    var onClose: () -> Void = {}

    private var entries: [(keys: String, command: String)] = []
    /// First visible row of every column.
    private var top = 0
    private var pendingG = false
    private var wheelRemainder: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.97).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func show(_ keymap: Keymap) {
        entries = keymap.bindings.map { binding in
            (binding.keys.map(\.description).joined(), binding.text)
        }
        top = 0
        pendingG = false
        needsDisplay = true
        report()
    }

    // MARK: Geometry

    private var columns: Int {
        max(1, Int((bounds.width - 2 * Self.padding) / Self.columnWidth))
    }

    /// Rows per column: the list is filled down each column in turn.
    private var rowsPerColumn: Int {
        (entries.count + columns - 1) / columns
    }

    private var visibleRows: Int {
        max(1, Int((bounds.height - Self.headerHeight - Self.padding) / Self.rowHeight))
    }

    private var maxTop: Int {
        max(0, rowsPerColumn - visibleRows)
    }

    override func layout() {
        super.layout()
        top = min(top, maxTop)
    }

    private func scroll(to row: Int) {
        let clamped = min(max(0, row), maxTop)
        guard clamped != top else {
            return
        }
        top = clamped
        needsDisplay = true
        report()
    }

    /// For the smoke test: where the list is, under SVIEW_DEBUG.
    private func report() {
        DebugLog.log("help top \(top) of \(maxTop) rows \(rowsPerColumn) visible \(visibleRows)")
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let header = "Keys    j k scroll, ctrl-d ctrl-u half page, gg G top and bottom, ? q esc close"
        (header as NSString).draw(
            with: NSRect(x: Self.padding, y: 14, width: bounds.width - 2 * Self.padding, height: 18),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        let perColumn = rowsPerColumn
        let shownRows = min(visibleRows, perColumn - top)
        guard shownRows > 0 else {
            return
        }
        let keyAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let commandAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        for column in 0..<columns {
            let x = Self.padding + CGFloat(column) * Self.columnWidth
            for line in 0..<shownRows {
                let index = column * perColumn + top + line
                guard index < entries.count else {
                    break
                }
                let y = Self.headerHeight + CGFloat(line) * Self.rowHeight
                let keys = entries[index].keys as NSString
                let width = keys.size(withAttributes: keyAttributes).width
                keys.draw(at: NSPoint(x: x + max(0, Self.keysWidth - width), y: y), withAttributes: keyAttributes)
                (entries[index].command as NSString).draw(
                    with: NSRect(x: x + Self.keysWidth + 8, y: y, width: Self.columnWidth - Self.keysWidth - 16, height: Self.rowHeight),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: commandAttributes
                )
            }
        }
        // A thin bar on the right shows where the visible rows sit.
        if maxTop > 0 {
            let track = bounds.height - Self.headerHeight - Self.padding
            let height = max(24, track * CGFloat(visibleRows) / CGFloat(perColumn))
            let y = Self.headerHeight + (track - height) * CGFloat(top) / CGFloat(maxTop)
            NSColor(white: 1, alpha: 0.25).setFill()
            NSBezierPath(roundedRect: NSRect(x: bounds.width - 8, y: y, width: 4, height: height), xRadius: 2, yRadius: 2).fill()
        }
    }

    // MARK: Keys, wheel and mouse

    override func keyDown(with event: NSEvent) {
        guard let key = KeyTranslator.key(for: event) else {
            return
        }
        let control = key.modifiers.contains(.control)
        let wasG = pendingG
        pendingG = false
        switch (key.base, control) {
        case ("j", false), ("down", false):
            scroll(to: top + 1)
        case ("k", false), ("up", false):
            scroll(to: top - 1)
        case ("d", true):
            scroll(to: top + visibleRows / 2)
        case ("u", true):
            scroll(to: top - visibleRows / 2)
        case (" ", false):
            scroll(to: top + (key.modifiers.contains(.shift) ? -visibleRows : visibleRows))
        case ("pagedown", false):
            scroll(to: top + visibleRows)
        case ("pageup", false):
            scroll(to: top - visibleRows)
        case ("G", false), ("end", false):
            scroll(to: maxTop)
        case ("home", false):
            scroll(to: 0)
        case ("g", false):
            if wasG {
                scroll(to: 0)
            } else {
                pendingG = true
            }
        case ("?", false), ("q", false), ("esc", _):
            onClose()
        default:
            // Everything else is swallowed: the viewer behind does not react.
            break
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * Self.rowHeight
        wheelRemainder -= delta
        let rows = Int(wheelRemainder / Self.rowHeight)
        if rows != 0 {
            wheelRemainder -= CGFloat(rows) * Self.rowHeight
            scroll(to: top + rows)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }
}
