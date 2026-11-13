import Foundation
import WebKit

/// One buffer: a web view, its hint controller, and enough bookkeeping to
/// suspend it when it has been idle for a while.
@MainActor
final class Tab {
    let webView: WKWebView
    let hints: HintController

    private(set) var lastAccessed = Date()
    private(set) var isSuspended = false

    /// Fired when the title or URL changes, so the status line and the buffer
    /// list follow along.
    var onChange: ((Tab) -> Void)?

    private var suspendedURL: URL?
    /// Kept so a suspended tab still has a name in the buffer list, where the
    /// web view no longer reports one.
    private var cachedTitle = ""
    private var observations: [NSKeyValueObservation] = []

    var title: String {
        isSuspended ? cachedTitle : (webView.title ?? cachedTitle)
    }

    var url: URL? {
        isSuspended ? suspendedURL : webView.url
    }

    /// What the buffer list shows and fuzzy matching runs against.
    var displayName: String {
        let name = title.isEmpty ? L("Untitled") : title
        guard let address = url?.absoluteString, !address.isEmpty else { return name }
        return "\(name) — \(address)"
    }

    init(configuration: WKWebViewConfiguration) {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        self.webView = webView
        self.hints = HintController(webView: webView)

        observations = [
            webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isSuspended else { return }
                    if let title = webView.title, !title.isEmpty {
                        self.cachedTitle = title
                    }
                    self.onChange?(self)
                }
            },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.onChange?(self)
                }
            },
        ]
    }

    /// Stops the page and detaches the view, so a deleted buffer leaves
    /// nothing running or on screen.
    func teardown() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        observations = []
        onChange = nil
    }

    /// Restores a buffer from a saved session as if it had been suspended:
    /// named and listed, but not loaded until it is first shown.
    func restore(url: URL, title: String) {
        suspendedURL = url
        cachedTitle = title
        isSuspended = true
    }

    func load(_ url: URL) {
        isSuspended = false
        suspendedURL = nil
        webView.load(URLRequest(url: url))
    }

    /// Marks the tab as used, restoring it if it had been suspended.
    func touch() {
        lastAccessed = Date()
        if isSuspended {
            resume()
        }
    }

    /// Drops the page to free its memory but keeps the tab and its name,
    /// remembering where to return to.
    /// Suspends the tab unless it is playing something.
    ///
    /// Suspension navigates to about:blank, so a background tab playing music
    /// would fall silent and lose its place. Every frame is asked, because the
    /// player is often in a cross-origin iframe that the main frame cannot
    /// see into.
    func suspendIfQuiet() {
        guard !isSuspended, let current = webView.url, current.scheme != "about" else { return }
        let frames: [WKFrameInfo?] =
            [nil] + FrameRegistry.shared.subframes(of: webView).map { $0.frame }
        askIfPlaying(frames, from: 0) { [weak self] playing in
            guard let self, !playing else { return }
            suspend()
        }
    }

    private func askIfPlaying(
        _ frames: [WKFrameInfo?],
        from index: Int,
        then finish: @escaping (Bool) -> Void
    ) {
        guard index < frames.count else {
            finish(false)
            return
        }
        let script = "typeof vimbaIsPlayingMedia === 'function' ? vimbaIsPlayingMedia() : false"
        webView.evaluateJavaScript(script, in: frames[index], in: .page) { [weak self] result in
            guard let self else { return }
            // A frame that has gone away cannot be playing anything.
            if case .success(let value) = result, (value as? NSNumber)?.boolValue == true {
                finish(true)
                return
            }
            askIfPlaying(frames, from: index + 1, then: finish)
        }
    }

    func suspend() {
        guard !isSuspended, let current = webView.url, current.scheme != "about" else { return }
        suspendedURL = current
        isSuspended = true
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        onChange?(self)
    }

    private func resume() {
        guard let target = suspendedURL else { return }
        suspendedURL = nil
        // Without this the tab stays marked suspended for the rest of its
        // life, so `url` keeps reading the address it no longer holds - which
        // left resumed buffers out of the saved session and showed a stale
        // name in the buffer list.
        isSuspended = false
        webView.load(URLRequest(url: target))
        onChange?(self)
    }
}
