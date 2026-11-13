import AppKit
import WebKit

/// Owns the browser window, its web view, the status line and the command bar,
/// and performs the actions that key bindings request.
@MainActor
final class BrowserWindowController: NSWindowController {
    /// The focused pane's web view. Reassigned whenever focus or the displayed
    /// buffer changes, so the rest of the controller can keep saying `webView`.
    private(set) var webView: WKWebView

    private var focusedPane: Pane { panes[focusedIndex] }
    private var currentTab: Tab { focusedPane.tab }

    private let splitView = NSSplitView()
    private var panes: [Pane] = []
    private var focusedIndex = 0
    private var tabs: TabManager!
    private let statusBar = StatusBarView()
    private let commandBar = CommandBarView()
    private let completions = CompletionView()
    private let keyGuide = KeyGuideView()
    private let bookmarks = BookmarkStore()
    /// Whether the completion list is currently offering command names or an
    /// argument, which decides how an accepted entry is written back.
    private var completingCommandName = false
    /// Text kept in front of an accepted candidate, such as "obm ".
    private var completionPrefix = ""
    /// True once Tab has built a candidate list for the current input.
    private var completionActive = false
    /// Whether the command bar is taking a command or a search pattern.
    private var barPurpose: BarPurpose = .command
    private var lastSearch: String?
    private var lastSearchBackwards = false
    /// Popups are retained here; WebKit only holds the web view.
    private var popups: [PopupWindowController] = []
    private var input: InputController?
    private let hintsBridge = HintsBridge()
    private let frames = FrameRegistry.shared
    private let history = CommandHistory()
    private var progressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    /// Set on navigation failure and cleared on the next load, so a mistyped
    /// :open reports something instead of appearing to do nothing.
    private var statusMessage: String?

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Off by default in WKWebView, which is why video players cannot go
        // fullscreen until it is switched on.
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.applicationNameForUserAgent = Config.userAgentSuffix

        let contentController = WKUserContentController()
        if let hintsScript = Self.makeHintsUserScript() {
            contentController.addUserScript(hintsScript)
        }
        contentController.add(hintsBridge, name: HintsBridge.messageName)
        contentController.add(frames, name: FrameRegistry.messageName)
        configuration.userContentController = contentController

        let manager = TabManager(configuration: configuration)
        let first = manager.newTab()
        self.webView = first.webView


        let contentSize = Self.initialContentSize()
        // Chromeless by default: the close, minimise and zoom buttons and the
        // title bar they sit in are all gone, so the page starts at the top
        // edge and the status line is the only furniture.
        let chromeless = Config.windowChrome != "titled"
        let style: NSWindow.StyleMask = chromeless
            ? [.borderless, .miniaturizable, .resizable]
            : [.titled, .closable, .miniaturizable, .resizable]
        let window = BrowserWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = L("Vimba")
        window.contentMinSize = NSSize(width: 480, height: 320)
        // Without this, toggleFullScreen: silently does nothing and the green
        // button only zooms.
        window.collectionBehavior.insert(.fullScreenPrimary)

        super.init(window: window)

        self.tabs = manager
        manager.isVisible = { [weak self] tab in
            self?.panes.contains { $0.tab === tab } ?? false
        }
        manager.onTabChanged = { [weak self] tab in
            guard let self, tab === self.currentTab else { return }
            self.updateWindowTitle()
            self.refreshStatusLine()
        }

        commandBar.isHidden = true
        completions.isHidden = true
        window.contentView = makeContentView()
        commandBar.onTextChange = { [weak self] _ in
            self?.resetCompletion()
        }
        // Installing an Auto Layout content view can resize the window, so the
        // size and position are only settled once it is in place.
        window.setContentSize(contentSize)
        window.center()
        window.delegate = self
        startInput()
        hintsBridge.onStatus = { [weak self] source, raw in
            // Tabs and popups share this bridge, so statuses are routed by
            // whichever web view reported them.
            guard let self else { return }
            if let tab = self.tabs.tabs.first(where: { $0.webView === source }) {
                tab.hints.handle(raw: raw)
            } else {
                self.popups.first { $0.webView === source }?.hintController.handle(raw: raw)
            }
        }
        let pane = Pane(tab: first)
        panes = [pane]
        splitView.addArrangedSubview(pane)
        splitView.adjustSubviews()
        focusPane(at: 0)
        manager.startSuspending()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        // Dropping the controller must also drop the global key monitor.
        MainActor.assumeIsolated {
            input?.stop()
        }
    }

    func load(_ url: URL) {
        currentTab.load(url)
    }

    /// The preferred window size, never larger than the screen it opens on.
    private static func initialContentSize() -> NSSize {
        guard let visible = NSScreen.main?.visibleFrame else { return Config.windowSize }
        let margin: CGFloat = 40
        return NSSize(
            width: min(Config.windowSize.width, visible.width - margin),
            height: min(Config.windowSize.height, visible.height - margin)
        )
    }

    private func makeContentView() -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: Self.initialContentSize()))

        splitView.isVertical = true
        splitView.dividerStyle = .thin

        for subview in [splitView, statusBar, commandBar, completions, keyGuide] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: container.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // The command bar occupies the same strip as the status line.
            commandBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            commandBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            commandBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // Floats above the command bar, overlaying the page.
            completions.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            completions.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            completions.bottomAnchor.constraint(equalTo: commandBar.topAnchor),

            // Sits where the completion list does, but above the status line:
            // it only appears in normal mode, where the command bar is hidden.
            keyGuide.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            keyGuide.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            keyGuide.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
        ])

        return container
    }

    private func startInput() {
        let input = InputController(
            actions: self,
            commands: self,
            tabs: self,
            panes: self,
            guide: self,
            ownerWindow: window
        )
        input.onModeChange = { [weak self] _ in
            self?.refreshStatusLine()
        }
        input.start()
        self.input = input
    }

    /// Moves focus to a pane and points input, hints and observations at the
    /// buffer it is showing.
    private func focusPane(at index: Int) {
        guard panes.indices.contains(index) else { return }

        focusedIndex = index
        for (position, pane) in panes.enumerated() {
            pane.isFocused = position == index
        }

        let tab = focusedPane.tab
        tab.touch()
        webView = tab.webView
        statusMessage = nil

        tab.webView.uiDelegate = self
        tab.webView.navigationDelegate = self

        tab.hints.onFinish = { [weak self] mode in
            self?.input?.enterMode(mode)
            self?.refreshStatusLine()
        }
        tab.hints.onHover = { [weak self] target in
            self?.statusBar.leftText = target
        }
        input?.setHints(tab.hints)

        progressObservation = tab.webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshStatusLine() }
        }
        loadingObservation = tab.webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshStatusLine() }
        }

        window?.makeFirstResponder(tab.webView)
        updateWindowTitle()
        refreshStatusLine()
    }

    /// Shows `tab` in the focused pane. If another pane already has it, the two
    /// panes trade buffers, since a web view cannot appear twice.
    private func show(_ tab: Tab) {
        if let other = panes.firstIndex(where: { $0.tab === tab }) {
            guard other != focusedIndex else { return }
            let displaced = focusedPane.tab
            panes[other].show(displaced)
        }
        focusedPane.show(tab)
        focusPane(at: focusedIndex)
    }

    private func updateWindowTitle() {
        let title = currentTab.title
        let position = (tabs.index(of: currentTab) ?? 0) + 1
        let suffix = tabs.tabs.count > 1 ? " (\(position)/\(tabs.tabs.count))" : ""
        window?.title = (title.isEmpty ? L("vimba") : title) + suffix
    }

    private func refreshStatusLine() {
        if let statusMessage {
            statusBar.leftText = statusMessage
        } else if webView.isLoading {
            statusBar.leftText = StatusBarView.progressBar(webView.estimatedProgress)
                + (webView.url?.absoluteString ?? "")
        } else {
            statusBar.leftText = webView.url?.absoluteString ?? ""
        }
        statusBar.rightText = switch input?.mode ?? .normal {
        case .normal: ""
        case .insert: L("-- INSERT --")
        case .command: ""
        case .hint: currentTab.hints.indicator
        case .passthrough: L("-- PASS THROUGH --")
        }
    }

    private func evaluate(_ script: String) {
        // Fire and forget: the async form would carry a non-Sendable Any back.
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// vimb's hints.js plus its stylesheet, injected into every frame so the
    /// `hints` global is ready before hint mode starts.
    private static func makeHintsUserScript() -> WKUserScript? {
        guard let jsURL = Bundle.main.url(forResource: "hints", withExtension: "js", subdirectory: "js"),
              let cssURL = Bundle.main.url(forResource: "hints", withExtension: "css", subdirectory: "js"),
              let js = try? String(contentsOf: jsURL, encoding: .utf8),
              let css = try? String(contentsOf: cssURL, encoding: .utf8)
        else {
            return nil
        }

        let scrollURL = Bundle.main.url(forResource: "scroll", withExtension: "js", subdirectory: "js")
        let scrollJS = scrollURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""

        let clickableURL = Bundle.main.url(forResource: "clickable", withExtension: "js", subdirectory: "js")
        let clickableJS = clickableURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""

        let diagURL = Bundle.main.url(forResource: "diag", withExtension: "js", subdirectory: "js")
        let diagJS = diagURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""

        // Loaded second so its rules win over the vendored stylesheet.
        let themeURL = Bundle.main.url(forResource: "hints-theme", withExtension: "css", subdirectory: "js")
        let theme = themeURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""

        // Last, so anything in ~/.config/vimba/hints.css wins.
        let userCSS = Settings.userHintCSS

        let source = """
        \(js)
        \(scrollJS)
        \(clickableJS)
        \(diagJS)
        (function () {
            // Kept on window so hints.js can adopt the same rules into the
            // shadow root that holds the labels.
            window.vimbaHintCSS = \(JSLiteral.string(css + "\n" + theme + "\n" + userCSS));
            var style = document.createElement('style');
            style.textContent = window.vimbaHintCSS;
            (document.head || document.documentElement).appendChild(style);

            // A subframe is invisible to the app until it says so: this is the
            // only way to obtain a WKFrameInfo for it.
            // Identifies this document, so the app can tell two handles to
            // the same frame apart from two different frames.
            window.vimbaFrameId = 'f' + Math.random().toString(36).slice(2)
                + '-' + Date.now();

            if (window !== window.top) {
                // Read by the parent frame's hints.js, which then leaves this
                // frame's elements to the copy running here.
                window.vimbaFrameRegistered = true;
                try {
                    window.webkit.messageHandlers.\(FrameRegistry.messageName)
                        .postMessage(String(location.href));
                } catch (e) {}
            }
        })();
        """

        // Injected into every frame. The main frame's hints.js walks
        // same-origin subframes itself and nothing calls hints.init() in a
        // subframe yet, so no duplicate hint sets arise; what this buys today
        // is that each subframe registers itself, which is the prerequisite
        // for hinting cross-origin content.
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    /// Builds the candidate list for the line as typed. Called once, on the
    /// first Tab: cycling afterwards reuses this snapshot, because re-ranking
    /// against the text we just filled in collapses the list to one entry.
    @discardableResult
    private func prepareCompletions() -> Bool {
        if case .search = barPurpose { return false }
        let line = commandBar.text
        let candidates: [String]

        if line.contains(" ") {
            completingCommandName = false

            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard let name = parts.first else { return false }
            let argument = parts.count > 1 ? parts[1] : ""
            completionPrefix = name + " "

            let pool: [String]
            if CommandParser.bookmarkSaveNames.contains(name) {
                pool = bookmarks.directories
            } else if CommandParser.bookmarkOpenNames.contains(name) {
                pool = bookmarks.paths
            } else if CommandParser.bufferNames.contains(name) {
                pool = tabs.displayNames
            } else {
                return false
            }
            candidates = argument.isEmpty ? pool : FuzzyMatcher.rank(pool, query: argument)
        } else {
            // Before the first space the user is still naming the command.
            completingCommandName = true
            completionPrefix = ""
            candidates = line.isEmpty
                ? CommandParser.allNames
                : FuzzyMatcher.rank(CommandParser.allNames, query: line)
        }

        Log.debug("prepare: line=\(line.debugDescription) candidates=\(candidates.count) bookmarks=\(bookmarks.paths.count)")

        guard !candidates.isEmpty else {
            completions.hide()
            return false
        }

        completions.show(candidates)
        completionActive = true
        return true
    }

    /// Typing invalidates the snapshot, and hides the list: it only appears in
    /// response to Tab.
    private func resetCompletion() {
        Log.debug("reset: was active=\(completionActive)")
        completionActive = false
        completions.hide()
    }

    private func cycleCompletion(forward: Bool) {
        Log.debug("cycle: forward=\(forward) active=\(completionActive)")
        if !completionActive, !prepareCompletions() {
            Log.debug("cycle: nothing to complete")
            return
        }
        if forward {
            completions.selectNext()
        } else {
            completions.selectPrevious()
        }
        fillFromCompletion()
    }

    /// Writes the highlighted candidate back into the command bar.
    private func fillFromCompletion() {
        Log.debug("fill: selection=\(completions.selection ?? "nil")")
        guard let selection = completions.selection else { return }
        // A completed command name gets a trailing space, so the next Tab
        // completes its argument instead.
        commandBar.text = completingCommandName
            ? selection + " "
            : completionPrefix + selection
        commandBar.moveCaretToEnd()
    }

    /// Exact buffer name first, then the best fuzzy match.
    private func resolveTab(_ query: String) -> Tab? {
        if let exact = tabs.tab(named: query) {
            return exact
        }
        guard let name = FuzzyMatcher.rank(tabs.displayNames, query: query).first else {
            return nil
        }
        return tabs.tab(named: name)
    }

    /// Exact path first, then the best fuzzy match.
    private func resolveBookmark(_ query: String) -> Bookmark? {
        if let exact = bookmarks.bookmark(at: query) {
            return exact
        }
        guard let path = FuzzyMatcher.rank(bookmarks.paths, query: query).first else {
            return nil
        }
        return bookmarks.bookmark(at: path)
    }

    private func run(_ command: Command) {
        switch command {
        case .open(let url):
            load(url)
        case .quit:
            NSApp.terminate(nil)
        case .saveBookmark(let path):
            saveBookmark(at: path)
        case .openBookmark(let query):
            guard let match = resolveBookmark(query), let url = URL(string: match.url) else {
                statusBar.leftText = L("No matching bookmark")
                return
            }
            load(url)
        case .newTab(let target):
            let tab = tabs.newTab()
            defer { show(tab) }
            if let url = URLResolver.resolve(target) {
                tab.load(url)
            } else {
                tab.load(Config.startPage)
            }
        case .selectBuffer(let query):
            guard let tab = resolveTab(query) else {
                statusBar.leftText = L("No matching buffer")
                return
            }
            show(tab)
        case .closeBuffer(let query):
            let target = query.isEmpty ? currentTab : resolveTab(query)
            guard let target else {
                statusBar.leftText = L("No matching buffer")
                return
            }
            if tabs.close(target) {
                repointPanes(after: target)
            } else {
                statusBar.leftText = L("Last buffer stays open")
            }
        case .cookies(let filter):
            dumpCookies(matching: filter)
        case .evaluate(let script):
            report(script: script)
        case .diagnose(let delay, let needle):
            runDiagnostics(after: delay, needle: needle)
        case .openBookmarkInNewTab(let query):
            guard let match = resolveBookmark(query), let url = URL(string: match.url) else {
                statusBar.leftText = L("No matching bookmark")
                return
            }
            let tab = tabs.newTab()
            tab.load(url)
            show(tab)
        case .deleteBookmark(let query):
            guard let match = resolveBookmark(query) else {
                statusBar.leftText = L("No matching bookmark")
                return
            }
            bookmarks.remove(path: match.path)
            statusBar.leftText = "\(L("Removed")) \(match.path)"
        }
    }

    /// An empty path, or one ending in a separator, takes the host as its leaf,
    /// so `:sbm /social/` becomes `/social/facebook.com`.
    private func saveBookmark(at path: String) {
        guard let url = webView.url else { return }

        var target = path.trimmingCharacters(in: .whitespaces)
        if target.isEmpty || target.hasSuffix("/") {
            target += url.host() ?? "page"
        }

        bookmarks.add(path: target, url: url.absoluteString, title: webView.title ?? "")
        statusBar.leftText = "\(L("Bookmarked")) \(BookmarkPath.normalize(target))"
    }
}

extension BrowserWindowController: BrowserActions, CommandActions, TabActions, PaneActions {
    func scrollBy(lines: Int) {
        evaluate("vimbaScroll.by(\(lines * Config.scrollStep));")
    }

    func scrollBy(columns: Int) {
        evaluate("vimbaScroll.byX(\(columns * Config.scrollStep));")
    }

    func scrollBy(pages: Double) {
        evaluate("vimbaScroll.byPages(\(pages));")
    }

    func scrollToTop() {
        evaluate("vimbaScroll.toTop();")
    }

    func scrollToBottom() {
        evaluate("vimbaScroll.toBottom();")
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

    func beginCommand(prefilled: String) {
        barPurpose = .command
        commandBar.promptText = ":"
        statusBar.isHidden = true
        commandBar.activate(prefilled: prefilled)
        history.reset()
        resetCompletion()
    }

    func recallPreviousCommand() {
        guard case .command = barPurpose,
              let line = history.previous(startingFrom: commandBar.text)
        else {
            return
        }
        commandBar.text = line
        resetCompletion()
    }

    func recallNextCommand() {
        guard case .command = barPurpose, let line = history.next() else { return }
        commandBar.text = line
        resetCompletion()
    }

    func showKeyGuide(_ entries: [KeyGuideEntry]) {
        keyGuide.show(entries)
    }

    func hideKeyGuide() {
        keyGuide.hide()
    }

    func yankURL() {
        copyToClipboard(webView.url?.absoluteString)
    }

    /// The browser's equivalent of vim's relative path: everything after the
    /// host, which is what identifies the page within a site.
    func yankPath() {
        guard let url = webView.url, var path = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            copyToClipboard(nil)
            return
        }
        path.scheme = nil
        path.host = nil
        path.port = nil
        path.user = nil
        path.password = nil
        copyToClipboard(path.string)
    }

    private func copyToClipboard(_ text: String?) {
        guard let text, !text.isEmpty else {
            statusBar.leftText = L("No address to copy")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        statusBar.leftText = L("Copied") + " " + text
    }

    func beginSearch(backwards: Bool) {
        barPurpose = .search(backwards: backwards)
        commandBar.promptText = backwards ? "?" : "/"
        statusBar.isHidden = true
        commandBar.activate(prefilled: "")
        resetCompletion()
    }

    func beginCommandWithCurrentURL() {
        beginCommand(prefilled: "open \(webView.url?.absoluteString ?? "")")
    }

    func submitCommand(alternate: Bool) {
        let typed = commandBar.text
        let purpose = barPurpose
        // Search patterns have their own repeat, with n and N; keeping them
        // out of the command history leaves it useful for addresses.
        if case .command = purpose {
            history.record(typed)
        }
        dismissCommandBar()
        input?.enterMode(.normal)

        let line = alternate ? CommandParser.swapTarget(typed) : typed

        switch purpose {
        case .command:
            if let command = CommandParser.parse(line) {
                run(command)
            } else {
                statusBar.leftText = L("Not a command")
            }
        case .search(let backwards):
            lastSearch = line
            lastSearchBackwards = backwards
            performFind(line, backwards: backwards)
        }
    }

    func cancelCommand() {
        dismissCommandBar()
    }

    func selectNextCompletion() {
        cycleCompletion(forward: true)
    }

    func selectPreviousCompletion() {
        cycleCompletion(forward: false)
    }

    func splitVertically() {
        split(vertical: true)
    }

    func splitHorizontally() {
        split(vertical: false)
    }

    /// Splits with a new buffer showing the same page, since a web view cannot
    /// appear in two panes at once.
    private func split(vertical: Bool) {
        splitView.isVertical = vertical

        let hidden = tabs.tabs.first { candidate in
            !panes.contains { $0.tab === candidate }
        }
        let tab: Tab
        if let hidden {
            tab = hidden
        } else {
            tab = tabs.newTab()
            tab.load(currentTab.url ?? Config.startPage)
        }

        let pane = Pane(tab: tab)
        panes.append(pane)
        splitView.addArrangedSubview(pane)
        equalizePanes()
        focusPane(at: panes.count - 1)
        logPaneGeometry()
    }

    /// After a buffer is deleted, any pane showing it needs another one. A
    /// buffer cannot appear twice, so a pane with nothing free left to show is
    /// closed instead, unless it is the only pane.
    private func repointPanes(after deleted: Tab) {
        var closing: [Int] = []

        for (index, pane) in panes.enumerated() where pane.tab === deleted {
            let free = tabs.tabs.first { candidate in
                !panes.contains { $0.tab === candidate }
            }
            if let free {
                pane.show(free)
            } else if panes.count - closing.count > 1 {
                closing.append(index)
            } else if let any = tabs.tabs.first {
                pane.show(any)
            }
        }

        for index in closing.reversed() {
            panes.remove(at: index).removeFromSuperview()
        }
        if !closing.isEmpty {
            equalizePanes()
        }

        focusPane(at: min(focusedIndex, panes.count - 1))
    }

    /// Gives every pane an equal share. adjustSubviews() only preserves the
    /// existing proportions, which leaves a newly added pane at zero size.
    private func equalizePanes() {
        guard panes.count > 1 else { return }
        splitView.layoutSubtreeIfNeeded()

        let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        let thickness = splitView.dividerThickness
        let each = (total - thickness * CGFloat(panes.count - 1)) / CGFloat(panes.count)

        for divider in 0..<(panes.count - 1) {
            let position = (each + thickness) * CGFloat(divider + 1) - thickness
            splitView.setPosition(position, ofDividerAt: divider)
        }
    }

    private func logPaneGeometry() {
        guard Log.enabled else { return }
        splitView.layoutSubtreeIfNeeded()
        Log.debug("split: frame=\(splitView.frame) vertical=\(splitView.isVertical) arranged=\(splitView.arrangedSubviews.count)")
        for (index, pane) in panes.enumerated() {
            Log.debug("  pane[\(index)] frame=\(pane.frame) translates=\(pane.translatesAutoresizingMaskIntoConstraints) web=\(pane.tab.webView.frame)")
        }
        if let content = window?.contentView {
            Log.debug("  content=\(content.frame) window=\(window?.frame ?? .zero)")
        }
    }

    func closePane() {
        guard panes.count > 1 else {
            statusBar.leftText = L("Last pane stays open")
            return
        }
        // Unlike vim, the buffer goes with the pane. A window there is a view
        // onto a file that still exists on disk; here the pane *is* the page,
        // and a buffer no pane shows is a web view left running unseen.
        let pane = panes.remove(at: focusedIndex)
        let closed = pane.tab
        pane.removeFromSuperview()
        equalizePanes()
        focusPane(at: min(focusedIndex, panes.count - 1))

        if tabs.close(closed) {
            repointPanes(after: closed)
        }
    }

    func focusNextPane() {
        focusPane(at: (focusedIndex + 1) % panes.count)
    }

    func focusPreviousPane() {
        focusPane(at: focusedIndex == 0 ? panes.count - 1 : focusedIndex - 1)
    }

    func nextTab() {
        if let tab = tabs.tab(after: currentTab, offset: 1) {
            show(tab)
        }
    }

    func previousTab() {
        if let tab = tabs.tab(after: currentTab, offset: -1) {
            show(tab)
        }
    }

    func zoomIn() {
        setZoom(webView.pageZoom * Config.zoomStep)
    }

    func zoomOut() {
        setZoom(webView.pageZoom / Config.zoomStep)
    }

    func zoomReset() {
        setZoom(1)
    }

    @objc func zoomIn(_ sender: Any?) { zoomIn() }
    @objc func zoomOut(_ sender: Any?) { zoomOut() }
    @objc func zoomReset(_ sender: Any?) { zoomReset() }

    private func setZoom(_ value: CGFloat) {
        webView.pageZoom = min(max(value, Config.zoomRange.lowerBound), Config.zoomRange.upperBound)
        statusBar.rightText = "\(Int((webView.pageZoom * 100).rounded()))%"
    }

    func followSelection() {
        evaluate("if (window.vimbaFollowSelection) { vimbaFollowSelection(); }")
    }

    func findNext() {
        guard let lastSearch else { return }
        performFind(lastSearch, backwards: lastSearchBackwards)
    }

    func findPrevious() {
        guard let lastSearch else { return }
        performFind(lastSearch, backwards: !lastSearchBackwards)
    }

    func blurPageFocus() {
        evaluate("if (window.vimbaReleaseFocus) { vimbaReleaseFocus(); }")
    }

    /// Evaluates an expression in the page, writing the result or error to
    /// stderr and a short form to the status line.
    private func report(script: String) {
        guard !script.isEmpty else { return }
        webView.evaluateJavaScript(script) { [weak self] result, error in
            let outcome: String
            if let error {
                outcome = "error: \(error.localizedDescription)"
            } else {
                outcome = String(describing: result ?? "undefined")
            }
            FileHandle.standardError.write(Data("js> \(script)\n\(outcome)\n".utf8))
            self?.statusBar.leftText = outcome
        }
    }

    /// Runs diag.js and appends its report to ~/.config/vimba/diag.log.
    ///
    /// A log file rather than the status line: the report is far too long for
    /// one line, and stderr is only visible when the app was started from a
    /// terminal.
    private func runDiagnostics(after delay: Double, needle: String) {
        // `:diag trace` records every hint call and its result, which is the
        // only way to see what each frame did to a keystroke.
        if needle == "trace" || needle == "notrace" {
            Diagnostics.traceHints = (needle == "trace")
            Diagnostics.append("\n===== trace \(Diagnostics.traceHints ? "on" : "off") \(Date()) =====\n")
            statusBar.leftText = "hint trace \(Diagnostics.traceHints ? "on" : "off")"
            return
        }
        if delay > 0 {
            statusBar.leftText = L("Diagnosing in") + " \(Int(delay))s"
        }
        let script = "vimbaDiagnose(\(JSLiteral.string(needle)))"
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            webView.evaluateJavaScript(script) { [weak self] result, error in
                let body: String
                if let error {
                    body = "error: \(error.localizedDescription)"
                } else {
                    body = String(describing: result ?? "undefined")
                }
                guard let self else { return }
                let known = frames.subframes(of: webView)
                let header = "frames reporting vimba scripts: \(known.count)\n"
                    + known.map { " - \($0.url.prefix(110))" }.joined(separator: "\n")
                appendDiagnostics(header + "\n" + body)
            }
        }
    }

    private func appendDiagnostics(_ body: String) {
        Diagnostics.append("\n===== \(Date()) =====\n\(body)\n")
        statusBar.leftText = L("Wrote") + " ~/.config/vimba/diag.log"
    }

    /// Writes matching cookies to stderr, with expiry, so session loss can be
    /// diagnosed from evidence rather than guessed at.
    private func dumpCookies(matching filter: String) {
        let needle = filter.lowercased()
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            let matches = cookies
                .filter { needle.isEmpty || $0.domain.lowercased().contains(needle) }
                .sorted { ($0.domain, $0.name) < ($1.domain, $1.name) }

            var report = "--- \(matches.count) cookie(s) matching \(needle.isEmpty ? "*" : needle) ---\n"
            for cookie in matches {
                let expiry = cookie.expiresDate.map {
                    ISO8601DateFormatter().string(from: $0)
                } ?? "session"
                report += "\(cookie.domain)\t\(cookie.name)\texpires=\(expiry)"
                report += "\tsecure=\(cookie.isSecure)\n"
            }
            FileHandle.standardError.write(Data(report.utf8))

            self?.statusBar.leftText = "\(matches.count) cookie(s) written to stderr"
        }
    }

    private enum BarPurpose {
        case command
        case search(backwards: Bool)
    }

    /// Runs a find and reports the outcome, so a pattern with no match says so
    /// rather than appearing to do nothing.
    private func performFind(_ query: String, backwards: Bool) {
        guard !query.isEmpty else { return }

        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true

        webView.find(query, configuration: configuration) { [weak self] result in
            guard let self else { return }
            self.statusMessage = result.matchFound
                ? nil
                : "\(L("Pattern not found")): \(query)"
            if result.matchFound {
                self.statusBar.leftText = "\(backwards ? "?" : "/")\(query)"
            } else {
                self.refreshStatusLine()
            }
        }
    }

    private func dismissCommandBar() {
        resetCompletion()
        commandBar.deactivate()
        statusBar.isHidden = false
        refreshStatusLine()
    }
}


extension BrowserWindowController: KeyGuideActions {}

extension BrowserWindowController: WKUIDelegate {
    /// Without this, window.open() returns null and OAuth sign-in flows such
    /// as Google's simply never appear.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let popup = PopupWindowController(configuration: configuration, features: windowFeatures)
        popup.webView.uiDelegate = self
        popup.onClose = { [weak self, weak popup] in
            self?.popups.removeAll { $0 === popup }
        }
        popups.append(popup)
        popup.showWindow(nil)
        return popup.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let popup = popups.first(where: { $0.webView === webView }) else { return }
        popup.close()
        popups.removeAll { $0 === popup }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: L("OK"))
        alert.runModal()
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Cancel"))
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field

        let confirmed = alert.runModal() == .alertFirstButtonReturn
        completionHandler(confirmed ? field.stringValue : nil)
    }
}


extension BrowserWindowController: NSWindowDelegate {
    /// Caps the window at the screen it is on, so a wide piece of content can
    /// never push it past the display edges.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let visible = sender.screen?.visibleFrame else { return frameSize }
        return NSSize(
            width: min(frameSize.width, visible.width),
            height: min(frameSize.height, visible.height)
        )
    }
}


extension BrowserWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        statusMessage = nil
        // The frames of the outgoing page are gone, and so are their handles.
        frames.reset(webView)
        refreshStatusLine()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        statusMessage = nil
        refreshStatusLine()
    }

    /// Reported rather than swallowed: a mistyped :open otherwise looks like
    /// nothing happened at all.
    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        report(error)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        report(error)
    }

    private func report(_ error: any Error) {
        // A cancelled load is the normal result of navigating away mid-request.
        let code = (error as NSError).code
        guard code != NSURLErrorCancelled else { return }
        statusMessage = "\(L("Failed")): \(error.localizedDescription)"
        refreshStatusLine()
    }
}
