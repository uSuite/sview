import AppKit

/// The one-line prompt at the bottom of the window for `:`, `/` and rename
/// (SV-304, SV-305, SV-404). Enter submits, Esc cancels; focus returns to
/// the canvas either way.
final class CommandPromptView: NSView, NSTextFieldDelegate {
    var onSubmit: (String) -> Void = { _ in }
    var onCancel: () -> Void = {}
    /// Tab (or shift-tab when the flag is set): returns the new text, if any.
    var onTab: (String, Bool) -> String? = { _, _ in nil }

    private let prefixLabel = NSTextField(labelWithString: ":")
    private let field = NSTextField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        prefixLabel.font = font
        prefixLabel.textColor = .secondaryLabelColor
        field.font = font
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        for view in [prefixLabel, field] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            prefixLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            prefixLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.leadingAnchor.constraint(equalTo: prefixLabel.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 28),
        ])
        prefixLabel.setContentHuggingPriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    var text: String { field.stringValue }

    func begin(prefix: String, text: String) {
        prefixLabel.stringValue = prefix
        field.stringValue = text
        isHidden = false
        window?.makeFirstResponder(field)
        field.currentEditor()?.moveToEndOfDocument(nil)
    }

    func end() {
        isHidden = true
        field.stringValue = ""
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy selector: Selector
    ) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onSubmit(field.stringValue)
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            let backwards = selector == #selector(NSResponder.insertBacktab(_:))
            if let text = onTab(field.stringValue, backwards) {
                field.stringValue = text
                field.currentEditor()?.moveToEndOfDocument(nil)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel()
            return true
        case #selector(NSResponder.deleteBackward(_:)) where field.stringValue.isEmpty:
            // Backspace on an empty prompt closes it, as in vim.
            onCancel()
            return true
        default:
            return false
        }
    }
}
