import AppKit
import WebKit

/// A window opened by `window.open()`, such as an OAuth sign-in flow.
///
/// The web view must be built from the configuration WebKit hands over, and
/// must not be loaded here: WebKit performs the navigation itself once the
/// view is returned from the UI delegate.
///
/// Popups get their own modal input, but start in insert mode, since a popup
/// is almost always a form waiting to be typed into.
@MainActor
final class PopupWindowController: NSWindowController {
    let webView: WKWebView

    /// Called when the popup closes, so the opener can drop its reference.
    var onClose: (() -> Void)?

    /// Exposed so the opener can route hint statuses to the right window.
    private(set) var hintController: HintController!

    private let statusBar = StatusBarView()
    private var input: InputController?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?

    init(configuration: WKWebViewConfiguration, features: WKWindowFeatures) {
        let size = NSSize(
            width: features.width?.doubleValue ?? 560,
            height: features.height?.doubleValue ?? 680
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()

        super.init(window: window)

        window.contentView = makeContentView(size: size)
        window.delegate = self

        let hints = HintController(webView: webView)
        hintController = hints

        let input = InputController(
            actions: self,
            hints: hints,
            ownerWindow: window,
            initialMode: .insert
        )
        input.onModeChange = { [weak self] _ in self?.refreshStatusLine() }
        input.start()
        self.input = input

        hints.onFinish = { [weak self] mode in
            self?.input?.enterMode(mode)
            self?.refreshStatusLine()
        }
        hints.onHover = { [weak self] target in
            self?.statusBar.leftText = target
        }

        trackPageMetadata()
        refreshStatusLine()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        MainActor.assumeIsolated {
            input?.stop()
        }
    }

    private func makeContentView(size: NSSize) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))

        for subview in [webView, statusBar] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func trackPageMetadata() {
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.window?.title = webView.title ?? ""
            }
        }
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.refreshStatusLine()
            }
        }
    }

    private func refreshStatusLine() {
        statusBar.leftText = webView.url?.absoluteString ?? ""
        statusBar.rightText = switch input?.mode ?? .insert {
        case .insert: L("-- INSERT --")
        case .hint: hintController?.indicator ?? ""
        case .passthrough: L("-- PASS THROUGH --")
        default: ""
        }
    }

    private func evaluate(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}

extension PopupWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        input?.stop()
        onClose?()
    }
}

extension PopupWindowController: BrowserActions {
    func scrollBy(lines: Int) {
        evaluate("vimbScroll.by(\(lines * Config.scrollStep));")
    }

    func scrollBy(columns: Int) {
        evaluate("vimbScroll.byX(\(columns * Config.scrollStep));")
    }

    func scrollBy(pages: Double) {
        evaluate("vimbScroll.byPages(\(pages));")
    }

    func scrollToTop() {
        evaluate("vimbScroll.toTop();")
    }

    func scrollToBottom() {
        evaluate("vimbScroll.toBottom();")
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    func zoomIn() {
        webView.pageZoom = min(webView.pageZoom * Config.zoomStep, Config.zoomRange.upperBound)
    }

    func zoomOut() {
        webView.pageZoom = max(webView.pageZoom / Config.zoomStep, Config.zoomRange.lowerBound)
    }

    func zoomReset() {
        webView.pageZoom = 1
    }

    func followSelection() {
        evaluate("if (window.vimbFollowSelection) { vimbFollowSelection(); }")
    }

    func findNext() {}

    func findPrevious() {}

    func blurPageFocus() {
        evaluate("if (window.vimbReleaseFocus) { vimbReleaseFocus(); }")
    }
}
