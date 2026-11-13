import AppKit

/// Candidate list shown above the command bar while a path is being typed.
@MainActor
final class CompletionView: NSView {
    static let rowHeight: CGFloat = 20
    static let maxVisible = 8

    private(set) var items: [String] = []
    /// -1 until something is chosen, so the first Tab lands on the first row.
    private(set) var selectedIndex = -1

    private let stack = NSStackView()
    private var heightConstraint: NSLayoutConstraint?

    /// The highlighted candidate, if the list is showing anything.
    var selection: String? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let height = heightAnchor.constraint(equalToConstant: 0)
        heightConstraint = height

        NSLayoutConstraint.activate([
            height,
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ candidates: [String]) {
        items = Array(candidates.prefix(Self.maxVisible))
        selectedIndex = -1
        rebuild()
        Log.debug("show: in=\(candidates.count) items=\(items.count) hidden=\(isHidden)")
    }

    func hide() {
        items = []
        selectedIndex = -1
        rebuild()
    }

    func selectNext() {
        Log.debug("selectNext: items=\(items.count) index=\(selectedIndex)")
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
        rebuild()
        Log.debug("selectNext -> index=\(selectedIndex) selection=\(selection ?? "nil")")
    }

    func selectPrevious() {
        guard !items.isEmpty else { return }
        selectedIndex = selectedIndex <= 0 ? items.count - 1 : selectedIndex - 1
        rebuild()
    }

    private func rebuild() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, item) in items.enumerated() {
            let row = makeRow(item, selected: index == selectedIndex)
            // Added before the width constraint is activated: anchors need a
            // common ancestor, and activating one without it raises.
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }

        isHidden = items.isEmpty
        heightConstraint?.constant = CGFloat(items.count) * Self.rowHeight
    }

    private func makeRow(_ text: String, selected: Bool) -> NSView {
        let row = NSView()
        row.wantsLayer = true
        row.layer?.backgroundColor = selected
            ? NSColor.selectedContentBackgroundColor.cgColor
            : NSColor.clear.cgColor
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = .monospacedSystemFont(ofSize: 11, weight: selected ? .semibold : .regular)
        label.textColor = selected ? .alternateSelectedControlTextColor : .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        return row
    }
}
