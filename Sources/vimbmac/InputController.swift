import AppKit

/// Intercepts key events before the web view sees them.
///
/// This is what makes modal input possible at all: WKWebView consumes every
/// keystroke while page content has focus, so a local event monitor has to get
/// first refusal and decide, per mode, whether the page sees the key.
@MainActor
final class InputController {
    private(set) var mode: Mode = .normal

    /// Fired whenever the mode changes, so the status line can follow.
    var onModeChange: ((Mode) -> Void)?

    private weak var actions: BrowserActions?
    private weak var commands: CommandActions?
    private weak var hints: HintActions?
    private weak var tabs: TabActions?
    private weak var panes: PaneActions?
    private weak var ownerWindow: NSWindow?
    private var monitor: Any?

    /// Keys typed so far towards a binding, such as the first `g` of `gg`.
    private var pendingSequence: [KeyStroke] = []
    private let keymap = Keymap.load()

    init(
        actions: BrowserActions,
        commands: CommandActions? = nil,
        hints: HintActions? = nil,
        tabs: TabActions? = nil,
        panes: PaneActions? = nil,
        ownerWindow: NSWindow?,
        initialMode: Mode = .normal
    ) {
        self.actions = actions
        self.commands = commands
        self.hints = hints
        self.tabs = tabs
        self.panes = panes
        self.ownerWindow = ownerWindow
        self.mode = initialMode
    }

    func start() {
        // NSEvent is not Sendable, so the main-actor hop returns a Bool verdict
        // and the event itself never leaves this closure.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let forwardToPage = MainActor.assumeIsolated { self.shouldForward(event) }
            return forwardToPage ? event : nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// Points hint handling at a different web view, after a tab switch.
    func setHints(_ hints: HintActions?) {
        self.hints = hints
    }

    func enterMode(_ newMode: Mode) {
        setMode(newMode)
    }

    /// Returns true to let the key reach the page, false to swallow it.
    private func shouldForward(_ event: NSEvent) -> Bool {
        // Keys destined for another window, such as an OAuth popup, are none
        // of our business; modal input applies to the browser window only.
        let matches = event.window == nil || event.window === ownerWindow
        Log.debug("win: match=\(matches) owner=\(ownerWindow.map { ObjectIdentifier($0).debugDescription } ?? "nil") event=\(event.window.map { ObjectIdentifier($0).debugDescription } ?? "nil") mode=\(mode)")
        guard matches else { return true }

        // System chords such as Cmd-Q and Cmd-W stay with AppKit.
        guard !event.modifierFlags.contains(.command) else { return true }

        if event.keyCode == KeyCode.escape {
            pendingSequence.removeAll()
            if mode == .command {
                commands?.cancelCommand()
            }
            // Cleared unconditionally: if the mode ever desyncs from what the
            // page is showing, this is the only way back to a clean state.
            hints?.cancelHints()
            actions?.blurPageFocus()
            setMode(.normal)
            return false
        }

        Log.debug("key: code=\(event.keyCode) mode=\(mode) chars=\(event.charactersIgnoringModifiers ?? "")")

        switch mode {
        case .insert, .passthrough:
            return true
        case .command:
            if KeyCode.submitKeys.contains(event.keyCode) {
                commands?.submitCommand()
                return false
            }
            if event.keyCode == KeyCode.tab {
                if event.modifierFlags.contains(.shift) {
                    commands?.selectPreviousCompletion()
                } else {
                    commands?.selectNextCompletion()
                }
                return false
            }
            if event.keyCode == KeyCode.downArrow {
                commands?.selectNextCompletion()
                return false
            }
            if event.keyCode == KeyCode.upArrow {
                commands?.selectPreviousCompletion()
                return false
            }
            // The command bar is first responder, so let it do the typing.
            return true
        case .hint:
            handleHint(event)
            return false
        case .normal:
            // Arrows and paging keys reach the page even in normal mode, so
            // native <select> popups and custom dropdowns stay navigable.
            if KeyCode.navigationKeys.contains(event.keyCode) {
                return true
            }
            handleNormal(event)
            // Normal mode owns the keyboard: unbound keys must not reach the page.
            return false
        }
    }

    private func handleNormal(_ event: NSEvent) {
        guard let stroke = KeyStroke(event: event) else { return }

        pendingSequence.append(stroke)

        if let action = keymap.action(for: pendingSequence) {
            pendingSequence.removeAll()
            perform(action)
            return
        }

        // Keep waiting only while the sequence could still complete a binding.
        if !keymap.hasPrefix(pendingSequence) {
            pendingSequence.removeAll()
        }
    }

    private func perform(_ action: KeyAction) {
        switch action {
        case .scrollDown: actions?.scrollBy(lines: 1)
        case .scrollUp: actions?.scrollBy(lines: -1)
        case .scrollLeft: actions?.scrollBy(columns: -1)
        case .scrollRight: actions?.scrollBy(columns: 1)
        case .halfPageDown: actions?.scrollBy(pages: 0.5)
        case .halfPageUp: actions?.scrollBy(pages: -0.5)
        case .scrollTop: actions?.scrollToTop()
        case .scrollBottom: actions?.scrollToBottom()

        case .back: actions?.goBack()
        case .forward: actions?.goForward()
        case .reload: actions?.reload()

        case .zoomIn: actions?.zoomIn()
        case .zoomOut: actions?.zoomOut()
        case .zoomReset: actions?.zoomReset()

        case .insertMode:
            setMode(.insert)
        case .hintMode:
            guard let hints else { break }
            hints.beginHints()
            setMode(.hint)
        case .commandMode:
            guard let commands else { break }
            commands.beginCommand(prefilled: "")
            setMode(.command)
        case .commandOpen:
            guard let commands else { break }
            commands.beginCommand(prefilled: "open ")
            setMode(.command)
        case .commandOpenCurrent:
            guard let commands else { break }
            commands.beginCommandWithCurrentURL()
            setMode(.command)

        case .searchForward:
            guard let commands else { break }
            commands.beginSearch(backwards: false)
            setMode(.command)
        case .searchBackward:
            guard let commands else { break }
            commands.beginSearch(backwards: true)
            setMode(.command)
        case .followSelection: actions?.followSelection()
        case .searchNext: actions?.findNext()
        case .searchPrevious: actions?.findPrevious()

        case .passthroughMode:
            setMode(.passthrough)

        case .nextTab: tabs?.nextTab()
        case .previousTab: tabs?.previousTab()

        case .splitVertical: panes?.splitVertically()
        case .splitHorizontal: panes?.splitHorizontally()
        case .closePane: panes?.closePane()
        case .focusNextPane: panes?.focusNextPane()
        case .focusPreviousPane: panes?.focusPreviousPane()
        }
    }

    private func handleHint(_ event: NSEvent) {
        if KeyCode.submitKeys.contains(event.keyCode) {
            hints?.fireHint()
            return
        }
        if event.keyCode == KeyCode.delete {
            hints?.hintDeleteKey()
            return
        }
        if let key = event.charactersIgnoringModifiers?.first {
            hints?.hintInput(key)
        }
    }

    private func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        onModeChange?(newMode)
    }
}

enum KeyCode {
    static let escape: UInt16 = 53
    static let submitKeys: Set<UInt16> = [36, 76]  // Return, keypad Enter
    static let delete: UInt16 = 51
    static let tab: UInt16 = 48
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
    /// Arrows, page up/down, home and end.
    static let navigationKeys: Set<UInt16> = [123, 124, 125, 126, 116, 121, 115, 119]
}
