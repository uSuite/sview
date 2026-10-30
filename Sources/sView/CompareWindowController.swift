import AppKit
import SViewCore

/// Side by side compare of two images (SV-604) with zoom and pan kept in
/// step, for before and after captures. Keys: + - = e zoom, h j k l and
/// arrows pan, < > rotate, x swaps the sides, q or esc closes.
@MainActor
final class CompareWindowController: NSWindowController, NSWindowDelegate {
    var onClose: () -> Void = {}

    private var urls: [URL]
    private let canvases = [ImageCanvasView(), ImageCanvasView()]
    private let labels = [NSTextField(labelWithString: ""), NSTextField(labelWithString: "")]
    private var view = ViewState()
    private let pipeline = AppModel.shared.pipeline

    init(_ left: URL, _ right: URL) {
        urls = [left, right]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 480, height: 240)
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.center()
        layout(in: window)
        load()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private func layout(in window: NSWindow) {
        let root = NSView()
        let stack = NSStackView(views: canvases)
        stack.distribution = .fillEqually
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        for (index, canvas) in canvases.enumerated() {
            let other = canvases[1 - index]
            canvas.onKeyDown = { [weak self] event in
                self?.handle(event) ?? false
            }
            canvas.onZoom = { [weak self] zoom in
                self?.setZoom(zoom)
            }
            canvas.onOffsetChange = { offset in
                other.setOffset(offset)
            }
            canvas.onLayout = { [weak self] scale, _, _ in
                if index == 0 {
                    self?.view.effectiveScale = scale
                }
            }
            let label = labels[index]
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            canvas.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 10),
                label.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 8),
            ])
        }
        window.contentView = root
        window.initialFirstResponder = canvases[0]
    }

    private func load() {
        window?.title = "compare  \(urls[0].lastPathComponent)  |  \(urls[1].lastPathComponent)"
        for (index, url) in urls.enumerated() {
            labels[index].stringValue = url.lastPathComponent
            Task { @MainActor in
                do {
                    let info = try await pipeline.info(url)
                    let image = try await pipeline.image(url, maxPixelSize: 0)
                    canvases[index].show(image, pixelSize: CGSize(width: info.width, height: info.height), newFile: true)
                    canvases[index].apply(view: view, background: AppModel.shared.config.background)
                } catch {
                    labels[index].stringValue = "\(url.lastPathComponent): \(error)"
                }
            }
        }
    }

    private func apply() {
        for canvas in canvases {
            canvas.apply(view: view, background: AppModel.shared.config.background)
        }
    }

    private func setZoom(_ zoom: ViewState.Zoom) {
        view.zoom = zoom
        apply()
    }

    private func zoom(by factor: Double) {
        let base: Double
        if case .scale(let scale) = view.zoom {
            base = scale
        } else {
            base = canvases[0].currentScale
        }
        let range = ViewState.scaleRange
        setZoom(.scale(min(max(base * factor, range.lowerBound), range.upperBound)))
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let key = KeyTranslator.key(for: event), key.modifiers.isDisjoint(with: [.command, .control]) else {
            return false
        }
        switch key.base {
        case "+":
            zoom(by: ViewState.zoomStep)
        case "-":
            zoom(by: 1 / ViewState.zoomStep)
        case "=":
            setZoom(.fit)
        case "e":
            setZoom(.actual)
        case "h", "left":
            canvases[0].pan(dx: -1, dy: 0)
        case "l", "right":
            canvases[0].pan(dx: 1, dy: 0)
        case "k", "up":
            canvases[0].pan(dx: 0, dy: -1)
        case "j", "down":
            canvases[0].pan(dx: 0, dy: 1)
        case "<":
            view.quarterTurns = (view.quarterTurns + 3) % 4
            apply()
        case ">":
            view.quarterTurns = (view.quarterTurns + 1) % 4
            apply()
        case "x":
            urls.reverse()
            load()
        case "q", "esc":
            window?.performClose(nil)
        default:
            return false
        }
        return true
    }
}
