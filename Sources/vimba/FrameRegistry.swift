import WebKit

/// Records the subframes that have vimba's scripts loaded.
///
/// WebKit offers no way to enumerate a page's frames: a `WKFrameInfo` only
/// ever arrives attached to a message a frame sent. Each injected frame
/// therefore announces itself once, and the frame info that comes with that
/// message is what `evaluateJavaScript(_:in:in:)` needs to run anything in it
/// later. Without this, content inside a cross-origin iframe - Gmail's account
/// menu, an embedded payment form - is unreachable: the main frame's hints.js
/// can walk same-origin frames itself, but not those.
final class FrameRegistry: NSObject, WKScriptMessageHandler {
    static let messageName = "vimbaFrames"
    /// One map for the whole app, keyed by web view. Every window and
    /// popup shares the user content controller this is registered on, so
    /// a single instance is what receives the announcements.
    ///
    static let shared = FrameRegistry()

    struct Entry {
        let url: String
        let frame: WKFrameInfo
    }

    /// `nonisolated(unsafe)` because the type cannot be main-actor isolated
    /// while conforming to WKScriptMessageHandler. Every access is on the main
    /// actor regardless: the handler hops there before touching this, and the
    /// readers below are main-actor isolated.
    nonisolated(unsafe) private var frames: [ObjectIdentifier: [Entry]] = [:]

    @MainActor
    func subframes(of webView: WKWebView) -> [Entry] {
        frames[ObjectIdentifier(webView)] ?? []
    }

    /// Called when a web view starts a new page: the old frames are gone and
    /// their frame info is dead.
    @MainActor
    func reset(_ webView: WKWebView) {
        frames[ObjectIdentifier(webView)] = []
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let url = message.body as? String,
              let webView = message.webView,
              !message.frameInfo.isMainFrame
        else {
            return
        }
        let frame = message.frameInfo
        MainActor.assumeIsolated {
            var list = frames[ObjectIdentifier(webView)] ?? []
            // A frame that navigates announces itself again; keep the newest
            // handle rather than accumulating dead ones.
            list.removeAll { $0.url == url }
            list.append(Entry(url: url, frame: frame))
            frames[ObjectIdentifier(webView)] = list
        }
    }
}
