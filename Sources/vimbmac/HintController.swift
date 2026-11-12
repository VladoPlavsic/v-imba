import WebKit

/// Drives vimb's hints.js for one web view.
///
/// Shared by the browser window and any popup, so hint mode behaves the same
/// in both. Status strings arrive from the page through HintsBridge, which
/// routes them by web view.
@MainActor
final class HintController: HintActions {
    /// Called when a hint session ends, with the mode to return to.
    var onFinish: ((Mode) -> Void)?
    /// Called with the target of the focused hint, for the status line.
    var onHover: ((String) -> Void)?

    private weak var webView: WKWebView?
    private var filter = ""
    private var keysTyped = ""

    init(webView: WKWebView) {
        self.webView = webView
    }

    /// Mirrors vimb's input line: the keys and text typed so far.
    var indicator: String {
        var parts = [L("-- HINT --")]
        if !keysTyped.isEmpty {
            parts.append(keysTyped)
        }
        if !filter.isEmpty {
            parts.append("/\(filter)")
        }
        return parts.joined(separator: " ")
    }

    func beginHints() {
        filter = ""
        keysTyped = ""
        // Marking runs first so the freshly added attributes are in place when
        // hints.js evaluates its xpath.
        evaluate("if (window.vimbMarkClickable) { vimbMarkClickable(); }")
        call(
            "hints.init(\"o\", false, \(Config.maxHints), \(JSLiteral.string(Config.hintKeys)), false, false)"
        )
    }

    func hintInput(_ character: Character) {
        if Config.hintKeys.contains(character) {
            keysTyped.append(character)
            call("hints.update(\(JSLiteral.string(String(character))))")
        } else {
            filter.append(character)
            call("hints.filter(\(JSLiteral.string(filter)))")
        }
    }

    func hintDeleteKey() {
        if !filter.isEmpty {
            filter.removeLast()
            call("hints.filter(\(JSLiteral.string(filter)))")
        } else if !keysTyped.isEmpty {
            keysTyped.removeLast()
            call("hints.update(null)")
        }
    }

    func fireHint() {
        call("hints.fire()")
    }

    func cancelHints() {
        filter = ""
        keysTyped = ""
        // The argument removes hints.js's resize and scroll listeners; without
        // it they re-create the hints on the next scroll.
        evaluate("if (window.hints) { hints.clear(true); }")
    }

    /// Handles a status string reported by hints.js.
    func handle(raw: String) {
        switch HintStatus(raw: raw) {
        case .done, .data:
            finish(returningTo: .normal)
        case .insert:
            finish(returningTo: .insert)
        case .over(let target):
            onHover?(target)
        case .error, .unknown:
            break
        }
    }

    private func finish(returningTo mode: Mode) {
        cancelHints()
        onFinish?(mode)
    }

    private func call(_ expression: String) {
        evaluate(
            "window.webkit.messageHandlers.\(HintsBridge.messageName).postMessage(String(\(expression)));"
        )
    }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
}
