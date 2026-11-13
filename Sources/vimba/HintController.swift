import WebKit

/// Drives vimb's hints.js for one web view, across every frame of the page.
///
/// Shared by the browser window and any popup, so hint mode behaves the same
/// in both. Status strings arrive from the page through HintsBridge, which
/// routes them by web view.
///
/// **Why this coordinates frames.** hints.js can only walk same-origin
/// subframes; anything cross-origin - Gmail's account menu, an embedded
/// checkout - is invisible to it, so those elements could not be hinted at
/// all. The script now runs in every frame instead, and this class is what
/// makes the separate instances behave as one: it hands each frame the number
/// to continue labelling from, so labels stay unique page-wide, and it makes
/// sure exactly one frame holds the focused hint, since every instance would
/// otherwise focus its own first hint and a single Enter would click in
/// several frames at once.
@MainActor
final class HintController: HintActions {
    /// Called when a hint session ends, with the mode to return to.
    var onFinish: ((Mode) -> Void)?
    /// Called with the target of the focused hint, for the status line.
    var onHover: ((String) -> Void)?

    private weak var webView: WKWebView?
    private var filter = ""
    private var keysTyped = ""

    /// The frames taking part in the current session. `nil` is the main frame,
    /// which `evaluateJavaScript` addresses when given no frame.
    private var targets: [WKFrameInfo?] = [nil]
    /// Index into `targets` of the frame holding the focused hint, and so the
    /// only frame allowed to act on Enter.
    private var activeTarget: Int?

    /// What one frame reports about its own hints.
    private struct FrameState {
        let index: Int
        /// The label of this frame's focused hint, or nil if it has none.
        let label: String?
        /// Where the focused hint points, for the status line.
        let src: String
        /// How many hints the frame still shows under the current filter.
        let shown: Int
    }

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
        activeTarget = nil
        guard let webView else { return }
        // Main frame first, so it keeps the low numbers that are quickest to
        // type; subframes continue from where it left off.
        let candidates: [WKFrameInfo?] =
            [nil] + FrameRegistry.shared.subframes(of: webView).map { $0.frame }
        resolveTargets(from: candidates, index: 0, kept: [], seen: []) { [weak self] resolved in
            guard let self else { return }
            targets = resolved
            createHints(in: 0, startingAt: 0)
        }
    }

    /// Drops frame handles that are dead, or that address a frame already
    /// taking part.
    ///
    /// Two handles can name one frame: a frame that navigates announces itself
    /// again under its new URL, while the handle from its previous document
    /// stays valid and now evaluates in the new one. Left in, that frame gets
    /// hinted twice - two sets of labels over the same elements - and receives
    /// every keystroke twice, so its filter advances two digits at a time and
    /// matches nothing.
    private func resolveTargets(
        from candidates: [WKFrameInfo?],
        index: Int,
        kept: [WKFrameInfo?],
        seen: Set<String>,
        then finish: @escaping ([WKFrameInfo?]) -> Void
    ) {
        guard index < candidates.count else {
            finish(kept)
            return
        }
        let candidate = candidates[index]
        run("String(window.vimbaFrameId || '')", in: candidate) { [weak self] value in
            guard let self else { return }
            var kept = kept
            var seen = seen
            let token = (value as? String) ?? ""
            if candidate == nil {
                // The main frame always takes part, token or not.
                kept.append(nil)
                if !token.isEmpty {
                    seen.insert(token)
                }
            } else if !token.isEmpty, !seen.contains(token) {
                seen.insert(token)
                kept.append(candidate)
            }
            resolveTargets(
                from: candidates, index: index + 1, kept: kept, seen: seen, then: finish
            )
        }
    }

    /// Starts hints in one frame, then the next, each continuing the numbering
    /// of the last. Sequential because a frame's starting number is only known
    /// once the previous frame has reported how many hints it made.
    private func createHints(in index: Int, startingAt offset: Int) {
        guard index < targets.count else {
            resolveFocus()
            return
        }
        let keys = JSLiteral.string(Config.hintKeys)
        // Marking runs first so the freshly added attributes are in place when
        // hints.js evaluates its xpath.
        let script = """
        (function () {
            if (!window.hints) { return -1; }
            if (window.vimbaMarkClickable) { vimbaMarkClickable(); }
            hints.init("o", false, \(Config.maxHints), \(keys), false, false, \(offset));
            return hints.count();
        })()
        """
        run(script, in: targets[index]) { [weak self] value in
            guard let self else { return }
            let count = max((value as? NSNumber)?.intValue ?? 0, 0)
            createHints(in: index + 1, startingAt: offset + count)
        }
    }

    func hintInput(_ character: Character) {
        Diagnostics.trace("key '\(character)' keys='\(keysTyped)' filter='\(filter)' frames=\(targets.count)")
        if Config.hintKeys.contains(character) {
            keysTyped.append(character)
            broadcast("hints.update(\(JSLiteral.string(String(character))))")
        } else {
            filter.append(character)
            broadcast("hints.filter(\(JSLiteral.string(filter)))")
        }
    }

    func hintDeleteKey() {
        if !filter.isEmpty {
            filter.removeLast()
            broadcast("hints.filter(\(JSLiteral.string(filter)))")
        } else if !keysTyped.isEmpty {
            keysTyped.removeLast()
            broadcast("hints.update(null)")
        }
    }

    func fireHint() {
        guard let index = activeTarget, index < targets.count else { return }
        call("hints.fire()", in: targets[index])
    }

    func cancelHints() {
        filter = ""
        keysTyped = ""
        activeTarget = nil
        // The argument removes hints.js's resize and scroll listeners; without
        // it they re-create the hints on the next scroll.
        for target in targets {
            run("if (window.hints) { hints.clear(true); } null;", in: target, then: nil)
        }
        targets = [nil]
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

    // MARK: - Frame coordination

    /// Sends the same call to every frame, then settles which one keeps focus.
    private func broadcast(_ expression: String) {
        for target in targets {
            run("if (window.hints) { \(expression); } null;", in: target, then: nil)
        }
        resolveFocus()
    }

    /// Asks every frame what it is showing, then leaves the focused hint with
    /// one of them and clears it everywhere else.
    private func resolveFocus() {
        collectStates(from: 0, into: []) { [weak self] states in
            self?.applyFocus(states)
        }
    }

    private func collectStates(
        from index: Int,
        into accumulated: [FrameState],
        then finish: @escaping ([FrameState]) -> Void
    ) {
        guard index < targets.count else {
            finish(accumulated)
            return
        }
        run("window.hints ? hints.state() : null", in: targets[index]) { [weak self] value in
            guard let self else { return }
            var accumulated = accumulated
            if let json = value as? String, let state = Self.parse(json, index: index) {
                accumulated.append(state)
            }
            collectStates(from: index + 1, into: accumulated, then: finish)
        }
    }

    private static func parse(_ json: String, index: Int) -> FrameState? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return FrameState(
            index: index,
            label: object["label"] as? String,
            src: object["src"] as? String ?? "",
            shown: (object["shown"] as? NSNumber)?.intValue ?? 0
        )
    }

    private func applyFocus(_ states: [FrameState]) {
        // A frame whose label is exactly what has been typed wins outright:
        // that is the hint the user is looking at. Otherwise the earliest
        // frame with anything focused keeps it, which is the main frame while
        // nothing has been typed.
        Diagnostics.trace("states " + states.map { "[\($0.index) label=\($0.label ?? "-")]" }.joined())

        // vimb hides every hint when the typed keys match none, which leaves a
        // blank page and no way on but Esc. Undo the keystroke instead, so a
        // mistyped digit costs nothing. This terminates: each pass drops one
        // character and stops at the empty string.
        if states.allSatisfy({ $0.shown == 0 }), !keysTyped.isEmpty {
            keysTyped.removeLast()
            Diagnostics.trace("no match, reverting to keys='\(keysTyped)'")
            for target in targets {
                run("if (window.hints) { hints.update(null); } null;", in: target, then: nil)
            }
            resolveFocus()
            return
        }

        let exact = states.first { $0.label != nil && $0.label == keysTyped }
        let winner = exact ?? states.first { $0.label != nil }
        activeTarget = winner?.index

        for state in states where state.label != nil && state.index != activeTarget {
            run("if (window.hints) { hints.deactivate(); } null;", in: targets[state.index], then: nil)
        }
        if let winner, !winner.src.isEmpty {
            onHover?(winner.src)
        }
    }

    // MARK: - Evaluation

    /// Evaluates in one frame and reports the result back on the main actor.
    /// A frame that has gone away since it registered simply fails, which is
    /// why errors are logged rather than surfaced.
    private func run(
        _ script: String,
        in frame: WKFrameInfo?,
        then handler: ((Any?) -> Void)?
    ) {
        guard let webView else {
            handler?(nil)
            return
        }
        let label = frame == nil ? "main" : "sub"
        Diagnostics.trace("\(label) <- \(script.replacingOccurrences(of: "\n", with: " "))")
        webView.evaluateJavaScript(script, in: frame, in: .page) { result in
            switch result {
            case .success(let value):
                Diagnostics.trace("\(label) -> \(String(describing: value))")
                handler?(value)
            case .failure(let error):
                Diagnostics.trace("\(label) !! \(error.localizedDescription)")
                Log.debug("frame eval failed: \(error.localizedDescription)")
                handler?(nil)
            }
        }
    }

    /// Posts the expression's result to the bridge, which is how a status such
    /// as `DONE:` or `OVER:` gets back to the app.
    private func call(_ expression: String, in frame: WKFrameInfo?) {
        run(
            "window.webkit.messageHandlers.\(HintsBridge.messageName).postMessage(String(\(expression)));",
            in: frame,
            then: nil
        )
    }
}
