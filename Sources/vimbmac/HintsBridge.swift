import WebKit

/// Receives the status strings that vimb's hints.js returns, relayed from the
/// page through a script message because evaluateJavaScript results cannot
/// cross an actor boundary.
final class HintsBridge: NSObject, WKScriptMessageHandler {
    static let messageName = "vimbHints"

    /// Carries the reporting web view, so a status can be routed to the
    /// window that owns it rather than always to the main one.
    var onStatus: ((WKWebView, String) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let status = message.body as? String, let webView = message.webView else { return }
        MainActor.assumeIsolated {
            onStatus?(webView, status)
        }
    }
}
