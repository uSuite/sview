import AppKit
import SViewCore

/// The folder sidebar (SV-207, SV-303): parent, siblings and children with
/// image counts. It takes the keyboard while it shows: j k or arrows move,
/// enter, o, l or right opens, h or left goes to the parent, typing
/// filters (start with / when the first letter is one of j k h l o s),
/// backspace edits the filter, esc clears the filter or hands the keyboard
/// back to the canvas, s hides the sidebar.
final class SidebarView: NSView {
    static let width: CGFloat = 260
    private static let rowHeight: CGFloat = 22
    private static let headerHeight: CGFloat = 30

    var onOpen: (URL) -> Void = { _ in }
    var onSelectionChange: (URL?) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    var onHide: () -> Void = {}

    private var rows: [FolderEntry] = []
    private var shown: [FolderEntry] = []
    private var filterText = ""
    private var selected = 0
    private var scrollOffset: CGFloat = 0
    private(set) var folder: URL?
    private var loadGeneration = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.96).cgColor
        widthAnchor.constraint(equalToConstant: Self.width).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    private var hasFocus: Bool { window?.firstResponder === self }

    /// Lists `folder`'s neighbourhood off the main thread, selecting it.
    func load(_ newFolder: URL?) {
        guard newFolder?.path != folder?.path else {
            return
        }
        folder = newFolder
        filterText = ""
        loadGeneration += 1
        let generation = loadGeneration
        guard let newFolder else {
            rows = []
            applyFilter()
            return
        }
        Task { @MainActor in
            let entries = await FolderListing.entries(for: newFolder)
            guard generation == loadGeneration else {
                return
            }
            rows = entries
            applyFilter()
        }
    }

    private func applyFilter() {
        let pattern = filterText.hasPrefix("/") ? String(filterText.dropFirst()) : filterText
        shown = FolderListing.filter(rows, by: pattern)
        let current = shown.firstIndex { $0.isCurrent } ?? 0
        let firstMatch = filterText.isEmpty
            ? current
            : (shown.firstIndex { $0.kind != .parent && !$0.isCurrent } ?? current)
        select(firstMatch)
    }

    private func select(_ index: Int) {
        selected = shown.isEmpty ? 0 : min(max(0, index), shown.count - 1)
        scrollToSelection()
        onSelectionChange(shown.isEmpty ? nil : shown[selected].url)
        needsDisplay = true
    }

    // MARK: Drawing

    private var listHeight: CGFloat { bounds.height - Self.headerHeight }

    private func scrollToSelection() {
        let top = CGFloat(selected) * Self.rowHeight
        if top < scrollOffset {
            scrollOffset = top
        } else if top + Self.rowHeight > scrollOffset + listHeight {
            scrollOffset = top + Self.rowHeight - listHeight
        }
        scrollOffset = max(0, min(scrollOffset, CGFloat(shown.count) * Self.rowHeight - listHeight))
    }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let header = filterText.isEmpty
            ? (folder?.deletingLastPathComponent().lastPathComponent ?? "folders")
            : "filter: \(filterText)"
        (header as NSString).draw(
            at: NSPoint(x: 10, y: 8),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: 0, y: Self.headerHeight, width: bounds.width, height: listHeight).clip()
        for (index, row) in shown.enumerated() {
            let y = Self.headerHeight + CGFloat(index) * Self.rowHeight - scrollOffset
            guard y + Self.rowHeight >= Self.headerHeight, y <= bounds.height else {
                continue
            }
            let rect = NSRect(x: 0, y: y, width: bounds.width, height: Self.rowHeight)
            if index == selected {
                (hasFocus ? Brand.accent : NSColor(white: 1, alpha: 0.12)).setFill()
                rect.insetBy(dx: 4, dy: 1).fill()
            }
            let dim = row.imageCount == 0 && row.kind != .parent
            let colour = dim ? NSColor.tertiaryLabelColor : NSColor.labelColor
            let indent: CGFloat = row.kind == .child ? 26 : 10
            let attributes: [NSAttributedString.Key: Any] = [
                .font: row.isCurrent ? bold : font,
                .foregroundColor: colour,
            ]
            let count = row.imageCount > 0 ? "\(row.imageCount)" : ""
            let countWidth = (count as NSString).size(withAttributes: attributes).width
            let nameRect = NSRect(x: indent, y: y + 3, width: bounds.width - indent - countWidth - 22, height: 16)
            (row.name as NSString).draw(
                with: nameRect,
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: attributes
            )
            (count as NSString).draw(
                at: NSPoint(x: bounds.width - countWidth - 12, y: y + 3),
                withAttributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
            )
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Keys and mouse

    override func keyDown(with event: NSEvent) {
        let key = event.keyCode
        let character = event.charactersIgnoringModifiers ?? ""
        let typing = !filterText.isEmpty
        if key == 125 || (!typing && character == "j") {
            select(selected + 1)
        } else if key == 126 || (!typing && character == "k") {
            select(selected - 1)
        } else if [36, 76, 124].contains(key) || (!typing && (character == "o" || character == "l")) {
            openSelected()
        } else if key == 123 || (!typing && character == "h") {
            if let parent = rows.first(where: { $0.kind == .parent }) {
                onOpen(parent.url)
            }
        } else if key == 53 {
            if typing {
                filterText = ""
                applyFilter()
            } else {
                onDismiss()
            }
        } else if key == 51 {
            if typing {
                filterText.removeLast()
                applyFilter()
            }
        } else if !typing && character == "s" {
            onHide()
        } else if !typing && character == "/" {
            // Starts a filter whose first letter is a navigation key.
            filterText = "/"
            applyFilter()
        } else if let text = event.characters, text.count == 1, let typed = text.first,
            !typed.isNewline, typed.unicodeScalars.allSatisfy({ $0.value >= 32 }),
            event.modifierFlags.isDisjoint(with: [.command, .control])
        {
            filterText.append(typed)
            applyFilter()
        } else {
            super.keyDown(with: event)
        }
    }

    private func openSelected() {
        guard shown.indices.contains(selected) else {
            return
        }
        onOpen(shown[selected].url)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let y = convert(event.locationInWindow, from: nil).y - Self.headerHeight + scrollOffset
        let index = Int(y / Self.rowHeight)
        guard y >= 0, shown.indices.contains(index) else {
            return
        }
        select(index)
        if event.clickCount == 2 {
            openSelected()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        let limit = max(0, CGFloat(shown.count) * Self.rowHeight - listHeight)
        scrollOffset = min(max(0, scrollOffset - event.scrollingDeltaY * factor), limit)
        needsDisplay = true
    }
}
