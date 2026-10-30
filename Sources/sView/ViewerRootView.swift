import AppKit

/// Window content: accepts dropped files and shows a centred message when
/// there is no image. The canvas and overlays are added as subviews.
final class ViewerRootView: NSView {
    var onDrop: ([URL]) -> Void = { _ in }
    private let label = NSTextField(labelWithString: "")

    var message: String? {
        didSet {
            label.stringValue = message ?? ""
            updateLabel()
        }
    }

    /// Set while a pane covers the window (the key help), so the message
    /// does not show through it (FIXME-2).
    var messageSuppressed = false {
        didSet {
            updateLabel()
        }
    }

    private func updateLabel() {
        label.isHidden = message == nil || messageSuppressed
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 14)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? [] : .generic
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        guard !urls.isEmpty else {
            return false
        }
        onDrop(urls)
        return true
    }
}
