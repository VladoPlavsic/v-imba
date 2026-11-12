import AppKit

/// One split pane, showing a single buffer.
///
/// A web view can only live in one view hierarchy, so a buffer appears in at
/// most one pane at a time; the controller swaps buffers between panes rather
/// than duplicating them.
@MainActor
final class Pane: NSView {
    private(set) var tab: Tab

    var isFocused = false {
        didSet {
            layer?.borderColor = isFocused
                ? NSColor.controlAccentColor.cgColor
                : NSColor.clear.cgColor
        }
    }

    init(tab: Tab) {
        self.tab = tab
        super.init(frame: .zero)

        // NSSplitView lays its arranged subviews out with constraints when the
        // split view itself is constraint-based, so a pane must be too or it
        // never gets sized.
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.clear.cgColor

        show(tab)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ tab: Tab) {
        self.tab = tab

        for existing in subviews {
            existing.removeFromSuperview()
        }

        let web = tab.webView
        web.translatesAutoresizingMaskIntoConstraints = false
        addSubview(web)

        // Inset by the border so the focus ring stays visible.
        let inset: CGFloat = 2
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            web.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            web.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            web.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
    }
}
