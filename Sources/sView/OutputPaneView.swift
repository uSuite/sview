import AppKit
import SViewCore

/// Output of `:run` and `:run-shell` (SV-603): a scrollable pane over the
/// bottom of the canvas with the command, its output and exit status.
/// Esc closes it.
final class OutputPaneView: NSView {
    static let height: CGFloat = 220

    private let header = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.05, alpha: 0.95).cgColor
        header.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.lineBreakMode = .byTruncatingMiddle
        textView.isEditable = false
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 4)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        for view in [header, scrollView] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func showRunning(_ command: String) {
        header.stringValue = "$ \(command)    running…"
        textView.string = ""
        isHidden = false
    }

    func show(_ result: HookResult) {
        let status = result.timedOut ? "timed out" : "exit \(result.status)"
        header.stringValue = "$ \(result.command)    \(status)"
        textView.string = result.output.isEmpty ? "(no output)" : result.output
        textView.scrollToEndOfDocument(nil)
        isHidden = false
    }
}
