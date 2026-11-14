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

    /// Keeps the web view filling the pane.
    ///
    /// The guard matters: while the page is in element fullscreen the web view
    /// has been moved into WebKit's own window, and forcing a frame on it
    /// there is what leaves a black rectangle behind.
    override func layout() {
        super.layout()
        guard tab.webView.superview === self else { return }
        tab.webView.frame = bounds.insetBy(dx: Self.inset, dy: Self.inset)
    }

    /// Inset by the border width, so the focus ring stays visible.
    private static let inset: CGFloat = 2

    func show(_ tab: Tab) {
        self.tab = tab

        for existing in subviews {
            existing.removeFromSuperview()
        }

        // Deliberately an autoresizing mask rather than constraints, even
        // though the pane itself is constraint-based. Entering element
        // fullscreen makes WebKit move this very web view into a full-screen
        // window of its own; constraints pinned to this pane would follow it
        // there, against a superview it no longer has, which shows up as a
        // black frame with the audio still playing, and as an Auto Layout
        // crash on the way back out. A mask simply stops applying once the
        // view has a different parent.
        let web = tab.webView
        web.translatesAutoresizingMaskIntoConstraints = true
        web.frame = bounds.insetBy(dx: Self.inset, dy: Self.inset)
        web.autoresizingMask = [.width, .height]
        addSubview(web)
        needsLayout = true
    }
}
