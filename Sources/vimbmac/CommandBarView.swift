import AppKit

/// The `:` command line, shown in place of the status line while command mode
/// is active.
@MainActor
final class CommandBarView: NSView, NSTextFieldDelegate {
    static let height: CGFloat = 22

    private let prompt = NSTextField(labelWithString: ":")

    /// ":" for a command, "/" or "?" for a search.
    var promptText: String {
        get { prompt.stringValue }
        set { prompt.stringValue = newValue }
    }
    private let field = NSTextField()

    /// Fired on every edit, so completions can follow what is being typed.
    var onTextChange: ((String) -> Void)?

    /// True while the bar writes to itself, so completion fills are not
    /// mistaken for the user typing.
    private var isWritingProgrammatically = false

    var text: String {
        get { field.currentEditor()?.string ?? field.stringValue }
        set {
            isWritingProgrammatically = true
            defer { isWritingProgrammatically = false }

            // While the field is first responder the field editor is
            // authoritative; writing stringValue as well makes the two fight.
            if let editor = field.currentEditor() {
                editor.string = newValue
            } else {
                field.stringValue = newValue
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        prompt.font = font
        field.font = font
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = true
        field.delegate = self

        for subview in [prompt, field] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            prompt.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            prompt.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.leadingAnchor.constraint(equalTo: prompt.trailingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !isWritingProgrammatically else { return }
        onTextChange?(text)
    }

    /// Moves the caret to the end, used after a completion is accepted.
    func moveCaretToEnd() {
        field.currentEditor()?.selectedRange = NSRange(location: text.count, length: 0)
    }

    /// Shows the bar and puts the caret at the end of the pre-filled text.
    func activate(prefilled: String) {
        text = prefilled
        isHidden = false
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: prefilled.count, length: 0)
    }

    func deactivate() {
        isHidden = true
        text = ""
        window?.makeFirstResponder(nil)
    }
}
