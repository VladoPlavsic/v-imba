import Foundation

/// What every window with a web view can do. Keeps the input layer independent
/// of the window and web view it drives.
@MainActor
protocol BrowserActions: AnyObject {
    func scrollBy(lines: Int)
    func scrollBy(columns: Int)
    func scrollBy(pages: Double)
    func scrollToTop()
    func scrollToBottom()
    func goBack()
    func goForward()
    func reload()

    func zoomIn()
    func zoomOut()
    func zoomReset()

    /// Clicks the element containing the current selection.
    func followSelection()

    func findNext()
    func findPrevious()

    /// Drops DOM focus and releases the scroll target.
    func blurPageFocus()
}

/// Implemented only by windows that have a command bar, so popups can take
/// part in modal input without pretending to support `:`.
@MainActor
protocol CommandActions: AnyObject {
    func beginCommand(prefilled: String)
    /// Opens the bar as a search prompt rather than a command line.
    func beginSearch(backwards: Bool)
    func beginCommandWithCurrentURL()
    func submitCommand()
    func cancelCommand()
    func selectNextCompletion()
    func selectPreviousCompletion()
}

/// Implemented only by windows that run the hint script.
@MainActor
protocol HintActions: AnyObject {
    func beginHints()
    func hintInput(_ character: Character)
    func hintDeleteKey()
    func fireHint()
    func cancelHints()
}

/// Implemented only by windows that hold buffers, so popups stay out of it.
@MainActor
protocol TabActions: AnyObject {
    func nextTab()
    func previousTab()
}

/// Window commands, reached through the Ctrl-w prefix.
@MainActor
protocol PaneActions: AnyObject {
    func splitVertically()
    func splitHorizontally()
    func closePane()
    func focusNextPane()
    func focusPreviousPane()
}
