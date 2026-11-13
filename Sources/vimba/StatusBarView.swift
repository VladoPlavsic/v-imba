import AppKit

/// Bottom status line: current URL on the left, mode indicator on the right,
/// mirroring vimb's layout.
@MainActor
final class StatusBarView: NSView {
    static let height: CGFloat = 22

    private let leftLabel = StatusBarView.makeLabel(alignment: .left)
    private let rightLabel = StatusBarView.makeLabel(alignment: .right)

    var leftText: String {
        get { leftLabel.stringValue }
        set { leftLabel.stringValue = newValue }
    }

    /// A vim-style load meter, rendered in text so it sits inline with the URL.
    static func progressBar(_ fraction: Double) -> String {
        let width = 10
        let filled = max(0, min(width, Int((fraction * Double(width)).rounded())))
        return "[" + String(repeating: "=", count: filled)
            + String(repeating: " ", count: width - filled) + "] "
    }

    var rightText: String {
        get { rightLabel.stringValue }
        set { rightLabel.stringValue = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        for label in [leftLabel, rightLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            leftLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            leftLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            rightLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: leftLabel.trailingAnchor, constant: 8
            ),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func makeLabel(alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingMiddle
        // A label's intrinsic width is its whole string, which would force the
        // window wider than the screen on a long URL. Let it truncate instead.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }
}
