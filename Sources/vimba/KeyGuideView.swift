import AppKit

/// One line of the key guide: a key that can follow what has been typed.
struct KeyGuideEntry {
    let key: String
    let label: String
    /// A group leads to further keys rather than doing something itself.
    let isGroup: Bool
}

/// which-key style panel listing the keys that can follow a pending sequence.
///
/// Shown as soon as a prefix is typed, with no delay, matching the
/// `delay = 0` in his nvim which-key config.
@MainActor
final class KeyGuideView: NSView {
    private static let rowHeight: CGFloat = 20
    private static let maxRows = 10
    private static let maxColumns = 4

    private let columns = NSStackView()
    private var heightConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        isHidden = true

        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = 24
        columns.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        columns.translatesAutoresizingMaskIntoConstraints = false
        addSubview(columns)

        let height = heightAnchor.constraint(equalToConstant: 0)
        heightConstraint = height

        NSLayoutConstraint.activate([
            height,
            columns.leadingAnchor.constraint(equalTo: leadingAnchor),
            columns.topAnchor.constraint(equalTo: topAnchor),
            columns.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ entries: [KeyGuideEntry]) {
        rebuild(with: entries)
    }

    func hide() {
        rebuild(with: [])
    }

    private func rebuild(with entries: [KeyGuideEntry]) {
        for view in columns.arrangedSubviews {
            columns.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard !entries.isEmpty else {
            heightConstraint?.constant = 0
            isHidden = true
            return
        }

        // Fill each column top to bottom before starting the next, which is
        // how which-key reads.
        let perColumn = min(
            Self.maxRows, Int(ceil(Double(entries.count) / Double(Self.maxColumns)))
        )
        var index = 0
        while index < entries.count, columns.arrangedSubviews.count < Self.maxColumns {
            let slice = entries[index..<min(index + perColumn, entries.count)]
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 0
            for entry in slice {
                column.addArrangedSubview(makeRow(entry))
            }
            columns.addArrangedSubview(column)
            index += perColumn
        }

        let rows = min(perColumn, Self.maxRows)
        heightConstraint?.constant = CGFloat(rows) * Self.rowHeight + 8
        isHidden = false
    }

    private func makeRow(_ entry: KeyGuideEntry) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6

        let key = NSTextField(labelWithString: entry.key)
        key.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        key.textColor = .controlAccentColor

        let arrow = NSTextField(labelWithString: "→")
        arrow.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        arrow.textColor = .tertiaryLabelColor

        let label = NSTextField(labelWithString: entry.label)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        // Groups are dimmer, so the keys that actually do something stand out.
        label.textColor = entry.isGroup ? .secondaryLabelColor : .labelColor

        for view in [key, arrow, label] {
            row.addArrangedSubview(view)
        }
        row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
        return row
    }
}
