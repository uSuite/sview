import AppKit
import SViewCore

/// The memo pane on the right (SV-402): the case folder's `.md` as plain
/// text, with the current capture's entry highlighted and scrolled into
/// view. Read-only; editing is parked (SV-605).
final class MemoPaneView: NSView {
    static let width: CGFloat = 380

    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private var memoURL: URL?
    private var stamp: Date?
    private var highlighted: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.96).cgColor
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: Self.width),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Shows `url`'s memo, re-reading it when it changed on disk, and
    /// highlights `fileName`'s entry.
    func show(memo url: URL, highlighting fileName: String?) {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if url != memoURL || modified != stamp {
            memoURL = url
            stamp = modified
            highlighted = nil
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? "cannot read \(url.lastPathComponent)"
            textView.textStorage?.setAttributedString(
                NSAttributedString(
                    string: text,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                        .foregroundColor: NSColor.labelColor,
                    ]
                )
            )
        }
        guard fileName != highlighted, let storage = textView.textStorage else {
            return
        }
        highlighted = fileName
        let all = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.backgroundColor, range: all)
        let ranges = fileName.map { Memo.highlights(for: $0, in: storage.string) } ?? []
        for range in ranges {
            storage.addAttribute(.backgroundColor, value: Brand.accent.withAlphaComponent(0.4), range: range)
        }
        if let first = ranges.first {
            textView.scrollRangeToVisible(first)
            centre(first)
        }
    }

    /// Scrolls so `range` sits mid-pane rather than at an edge.
    private func centre(_ range: NSRange) {
        guard let layout = textView.layoutManager, let container = textView.textContainer else {
            return
        }
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        let visible = scrollView.contentView.bounds.height
        let y = max(0, rect.midY + textView.textContainerInset.height - visible / 2)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(y, max(0, textView.frame.height - visible))))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
