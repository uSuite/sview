import AppKit
import QuartzCore
import SViewCore

/// The image surface (SV-105, SV-106, SV-107, SV-110): a layer-backed view
/// whose sublayer holds the decoded `CGImage`. Zoom, pan, rotation and flips
/// are layer geometry, so none of them re-decodes.
///
/// It owns the pan offset; zoom comes from `ViewState` and gestures are
/// reported back as zoom requests, so keys and gestures share one path.
final class ImageCanvasView: NSView {
    /// Pixels shown, reported after every layout: (scale, overflows h, overflows v).
    var onLayout: (Double, Bool, Bool) -> Void = { _, _, _ in }
    /// A decode of at least this many long-edge pixels would look sharper.
    var onNeedsPixels: (Int) -> Void = { _ in }
    /// Zoom requested by a gesture.
    var onZoom: (ViewState.Zoom) -> Void = { _ in }
    /// Scroll-wheel navigation when the image fits: +1 next, -1 previous.
    var onWheelStep: (Int) -> Void = { _ in }
    var onKeyDown: (NSEvent) -> Bool = { _ in false }
    /// A single click on the left (-1) or right (+1) half, when enabled (SV-309).
    var onClickSide: (Int) -> Void = { _ in }
    var clickNavigates = false
    var contextMenu: () -> NSMenu? = { nil }
    /// While a pane that owns input shows (the key help), the canvas ignores
    /// the mouse; a click on it calls `onBlockedClick` instead.
    var blocksInput: () -> Bool = { false }
    var onBlockedClick: () -> Void = {}
    /// The pan offset after any change, for the compare window's sync.
    var onOffsetChange: (CGPoint) -> Void = { _ in }
    private var reportedOffset: CGPoint = .zero

    var wheelZooms = false

    private let imageLayer = CALayer()
    private var image: CGImage?
    private var imageSize: CGSize = .zero
    private var view = ViewState()
    private var offset: CGPoint = .zero
    private var lastScale: Double = 0
    private var zoomAnchor: CGPoint?
    private var background = Config.Background.auto
    private var wheelAccumulator: CGFloat = 0
    private var dragStart: (point: CGPoint, offset: CGPoint)?
    private var dragged = false
    private var pendingClick: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        imageLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "transform": NSNull(),
            "contents": NSNull(),
        ]
        layer?.addSublayer(imageLayer)
        applyBackground()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: Content

    /// Shows `image` for a file whose oriented size is `pixelSize`. A new
    /// file recentres; a sharper decode of the same file keeps the position.
    func show(
        _ image: CGImage?,
        pixelSize: CGSize,
        newFile: Bool
    ) {
        self.image = image
        imageSize = pixelSize
        if newFile {
            offset = .zero
            lastScale = 0
            zoomAnchor = nil
        }
        // Core Animation attaches its render copy to the CGImage it is given.
        // Handing it a shallow copy keeps that copy off the cached original,
        // so it is freed when the layer moves on instead of doubling the
        // memory of every cached image.
        imageLayer.contents = image?.copy()
        imageLayer.isHidden = image == nil
        relayout()
    }

    var decodedLongEdge: Int {
        image.map { max($0.width, $0.height) } ?? 0
    }

    func apply(
        view newView: ViewState,
        background newBackground: Config.Background
    ) {
        let changed = newView != view
        view = newView
        if newBackground != background {
            background = newBackground
            applyBackground()
        }
        if changed {
            relayout()
        }
    }

    /// Sets the pan offset from a synced canvas; no echo back.
    func setOffset(_ newOffset: CGPoint) {
        guard newOffset != offset else {
            return
        }
        offset = newOffset
        reportedOffset = newOffset
        relayout()
        reportedOffset = offset
    }

    var currentScale: Double { lastScale }

    /// Pans by key steps, a tenth of the view per step (SV-106).
    func pan(dx: Int, dy: Int) {
        offset.x -= CGFloat(dx) * bounds.width * 0.1
        offset.y += CGFloat(dy) * bounds.height * 0.1
        relayout()
    }

    // MARK: Layout

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? 2
    }

    private var geometry: CanvasGeometry {
        CanvasGeometry(
            imageSize: imageSize,
            viewSize: bounds.size,
            backingScale: backingScale,
            quarterTurns: view.quarterTurns
        )
    }

    override func layout() {
        super.layout()
        relayout()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        relayout()
    }

    private func relayout() {
        guard imageSize.width > 0, bounds.width > 0 else {
            return
        }
        let geometry = geometry
        let scale = geometry.scale(for: view.zoom)
        if lastScale > 0, scale != lastScale {
            offset = CanvasGeometry.anchoredOffset(
                offset,
                anchor: zoomAnchor ?? .zero,
                from: lastScale,
                to: scale
            )
        }
        zoomAnchor = nil
        lastScale = scale
        offset = geometry.clamp(offset, scale: scale)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = geometry.layerSize(scale: scale)
        imageLayer.bounds = CGRect(origin: .zero, size: size)
        imageLayer.position = CGPoint(x: bounds.midX + offset.x, y: bounds.midY + offset.y)
        var transform = CATransform3DMakeRotation(-CGFloat(view.quarterTurns) * .pi / 2, 0, 0, 1)
        transform = CATransform3DScale(
            transform,
            view.flippedHorizontally ? -1 : 1,
            view.flippedVertically ? -1 : 1,
            1
        )
        imageLayer.transform = transform
        imageLayer.magnificationFilter = scale >= 2 ? .nearest : .linear
        imageLayer.contentsScale = backingScale
        CATransaction.commit()

        let overflow = geometry.overflows(scale: scale)
        onLayout(scale, overflow.horizontally, overflow.vertically)
        if offset != reportedOffset {
            reportedOffset = offset
            onOffsetChange(offset)
        }
        let needed = geometry.decodePixelSize(scale: scale)
        if image != nil, needed > decodedLongEdge + decodedLongEdge / 20 {
            onNeedsPixels(needed)
        }
    }

    // MARK: Background

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBackground()
    }

    private func applyBackground() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let auto = dark ? NSColor(white: 0.1, alpha: 1) : NSColor(white: 0.92, alpha: 1)
        switch background {
        case .auto:
            layer?.backgroundColor = auto.cgColor
            imageLayer.backgroundColor = nil
        case .checker:
            layer?.backgroundColor = auto.cgColor
            imageLayer.backgroundColor = Self.checkerColor(dark: dark).cgColor
        case .color(let red, let green, let blue):
            layer?.backgroundColor = CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
            imageLayer.backgroundColor = nil
        }
    }

    private static func checkerColor(dark: Bool) -> NSColor {
        let size = 16
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let light = dark ? NSColor(white: 0.3, alpha: 1) : NSColor(white: 1, alpha: 1)
            let shade = dark ? NSColor(white: 0.22, alpha: 1) : NSColor(white: 0.85, alpha: 1)
            light.setFill()
            rect.fill()
            shade.setFill()
            NSRect(x: 0, y: 0, width: size / 2, height: size / 2).fill()
            NSRect(x: size / 2, y: size / 2, width: size / 2, height: size / 2).fill()
            return true
        }
        return NSColor(patternImage: image)
    }

    // MARK: Events

    override func keyDown(with event: NSEvent) {
        if !onKeyDown(event) {
            super.keyDown(with: event)
        }
    }

    private func anchor(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x - bounds.midX, y: point.y - bounds.midY)
    }

    private func zoom(by factor: Double, at anchor: CGPoint) {
        guard lastScale > 0 else {
            return
        }
        zoomAnchor = anchor
        onZoom(.scale(lastScale * factor))
    }

    override func magnify(with event: NSEvent) {
        guard !blocksInput() else {
            return
        }
        zoom(by: 1 + Double(event.magnification), at: anchor(for: event))
    }

    override func scrollWheel(with event: NSEvent) {
        guard !blocksInput() else {
            return
        }
        let overflow = geometry.overflows(scale: lastScale)
        if event.modifierFlags.contains(.command) || (wheelZooms && !event.hasPreciseScrollingDeltas) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 100 : event.scrollingDeltaY / 10
            zoom(by: pow(1.25, Double(delta)), at: anchor(for: event))
            return
        }
        if overflow.horizontally || overflow.vertically {
            let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
            offset.x += event.scrollingDeltaX * factor
            offset.y -= event.scrollingDeltaY * factor
            relayout()
            return
        }
        // Image fits: the wheel or a deliberate swipe navigates (SV-309).
        wheelAccumulator += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 20
        if event.phase == .ended || event.momentumPhase == .ended {
            wheelAccumulator = 0
        }
        if abs(wheelAccumulator) >= 60 {
            onWheelStep(wheelAccumulator < 0 ? 1 : -1)
            wheelAccumulator = 0
        }
    }

    override func mouseDown(with event: NSEvent) {
        if blocksInput() {
            onBlockedClick()
            return
        }
        window?.makeFirstResponder(self)
        dragged = false
        if event.clickCount == 2 {
            pendingClick?.cancel()
            // Double-click toggles fit and actual size at the cursor (SV-309).
            zoomAnchor = anchor(for: event)
            onZoom(view.zoom == .fit ? .actual : .fit)
            return
        }
        dragStart = (convert(event.locationInWindow, from: nil), offset)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if abs(point.x - start.point.x) + abs(point.y - start.point.y) > 3 {
            dragged = true
        }
        offset = CGPoint(x: start.offset.x + point.x - start.point.x, y: start.offset.y + point.y - start.point.y)
        relayout()
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        guard clickNavigates, event.clickCount == 1, !dragged else {
            return
        }
        // Wait out a possible second click, which zooms instead.
        let side = convert(event.locationInWindow, from: nil).x < bounds.midX ? -1 : 1
        let click = DispatchWorkItem { [weak self] in
            self?.onClickSide(side)
        }
        pendingClick = click
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: click)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu()
    }
}
