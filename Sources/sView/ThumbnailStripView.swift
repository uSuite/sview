import AppKit
import SViewCore

/// The thumbnail strip along the bottom (SV-206): lazy thumbnails for the
/// visible range only, the current image outlined, marked images flagged,
/// click to jump, scroll wheel or trackpad to scroll. Plain layers in one
/// clipped view; it never takes keyboard focus from the canvas.
final class ThumbnailStripView: NSView {
    static let height: CGFloat = 96
    private static let inset: CGFloat = 8
    private static let spacing: CGFloat = 6
    private static let cellHeight = height - 2 * inset
    private static let cellWidth = (cellHeight * 1.4).rounded()

    var onSelect: (Int) -> Void = { _ in }
    let provider = ThumbnailProvider()

    private var urls: [URL] = []
    private var marked: Set<URL> = []
    private var current: Int?
    private var cells: [Int: ThumbnailCell] = [:]
    private var requested: Set<Int> = []
    /// Horizontal scroll position in points.
    private var offset: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.06, alpha: 0.92).cgColor
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var acceptsFirstResponder: Bool { false }

    override func layout() {
        super.layout()
        clampOffset()
        layoutCells()
    }

    func update(
        urls newURLs: [URL],
        current newCurrent: Int?,
        marked newMarked: Set<URL>
    ) {
        if newURLs != urls {
            urls = newURLs
            cells.values.forEach { $0.removeFromSuperlayer() }
            cells.removeAll()
            requested.removeAll()
            current = nil
            layoutCells()
        }
        if newMarked != marked {
            marked = newMarked
            for (index, cell) in cells {
                cell.isMarked = marked.contains(urls[index])
            }
        }
        guard newCurrent != current else {
            return
        }
        if let old = current {
            cells[old]?.isCurrent = false
        }
        current = newCurrent
        guard let index = newCurrent, urls.indices.contains(index) else {
            return
        }
        cells[index]?.isCurrent = true
        offset = x(of: index) + Self.cellWidth / 2 - bounds.width / 2
        clampOffset()
        layoutCells()
    }

    func invalidate(_ url: URL) {
        guard let index = urls.firstIndex(where: { $0.path == url.path }) else {
            return
        }
        requested.remove(index)
        Task { @MainActor in
            await provider.invalidate(url)
            layoutCells()
        }
    }

    // MARK: Layout

    private var contentWidth: CGFloat {
        x(of: urls.count) + Self.inset - Self.spacing
    }

    private func x(of index: Int) -> CGFloat {
        Self.inset + CGFloat(index) * (Self.cellWidth + Self.spacing)
    }

    private func frame(of index: Int) -> CGRect {
        CGRect(
            x: x(of: index) - offset,
            y: Self.inset,
            width: Self.cellWidth,
            height: Self.cellHeight
        )
    }

    private func clampOffset() {
        offset = min(max(0, offset), max(0, contentWidth - bounds.width))
    }

    /// Places cells for the visible range plus a screen either side,
    /// requesting their thumbnails once, and drops cells far away.
    private func layoutCells() {
        guard let host = layer else {
            return
        }
        let step = Self.cellWidth + Self.spacing
        let first = max(0, Int((offset - bounds.width) / step))
        let last = min(urls.count - 1, Int((offset + 2 * bounds.width) / step))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, cell) in cells where index < first || index > last {
            cell.removeFromSuperlayer()
            cells[index] = nil
            requested.remove(index)
        }
        if first <= last {
            for index in first...last {
                let cell = cells[index] ?? ThumbnailCell()
                if cells[index] == nil {
                    cells[index] = cell
                    host.addSublayer(cell)
                }
                cell.frame = frame(of: index)
                cell.isMarked = marked.contains(urls[index])
                cell.isCurrent = index == current
                if !requested.contains(index) {
                    requested.insert(index)
                    let url = urls[index]
                    Task { @MainActor in
                        let image = await provider.thumbnail(url)
                        guard index < urls.count, urls[index] == url else {
                            return
                        }
                        cells[index]?.image = image
                    }
                }
            }
        }
        CATransaction.commit()
    }

    // MARK: Events

    override func scrollWheel(with event: NSEvent) {
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        offset -= delta * (event.hasPreciseScrollingDeltas ? 1 : 12)
        clampOffset()
        layoutCells()
    }

    override func mouseDown(with event: NSEvent) {
        let position = convert(event.locationInWindow, from: nil).x + offset
        let index = Int((position - Self.inset) / (Self.cellWidth + Self.spacing))
        guard urls.indices.contains(index), position >= x(of: index), position <= x(of: index) + Self.cellWidth else {
            return
        }
        onSelect(index)
    }
}

private final class ThumbnailCell: CALayer {
    private let imageLayer = CALayer()
    private let markLayer = CALayer()

    override init() {
        super.init()
        cornerRadius = 4
        // A faint slot, so files without a thumbnail still show their place.
        backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        borderColor = Brand.accent.cgColor
        imageLayer.contentsGravity = .resizeAspect
        addSublayer(imageLayer)
        markLayer.backgroundColor = NSColor.systemYellow.cgColor
        markLayer.cornerRadius = 4
        markLayer.isHidden = true
        addSublayer(markLayer)
        actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        imageLayer.actions = actions
        markLayer.actions = actions
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        imageLayer.frame = bounds.insetBy(dx: 3, dy: 3)
        markLayer.frame = CGRect(x: bounds.maxX - 14, y: bounds.maxY - 14, width: 8, height: 8)
    }

    var image: CGImage? {
        didSet {
            imageLayer.contents = image
        }
    }

    var isMarked = false {
        didSet {
            markLayer.isHidden = !isMarked
        }
    }

    var isCurrent = false {
        didSet {
            borderWidth = isCurrent ? 2 : 0
        }
    }
}
