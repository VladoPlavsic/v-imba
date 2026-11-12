import Foundation

/// Everything a binding can be bound to. The raw values are the names used in
/// the config file.
enum KeyAction: String, CaseIterable {
    case scrollDown = "scroll-down"
    case scrollUp = "scroll-up"
    case scrollLeft = "scroll-left"
    case scrollRight = "scroll-right"
    case halfPageDown = "half-page-down"
    case halfPageUp = "half-page-up"
    case scrollTop = "scroll-top"
    case scrollBottom = "scroll-bottom"

    case back = "back"
    case forward = "forward"
    case reload = "reload"

    case zoomIn = "zoom-in"
    case zoomOut = "zoom-out"
    case zoomReset = "zoom-reset"

    case insertMode = "insert-mode"
    case hintMode = "hint-mode"
    case commandMode = "command-mode"
    case commandOpen = "command-open"
    case commandOpenCurrent = "command-open-current"

    case searchForward = "search-forward"
    case searchBackward = "search-backward"
    case searchNext = "search-next"
    case searchPrevious = "search-previous"

    /// Clicks whatever contains the selection, typically a search match.
    case followSelection = "follow-selection"

    case passthroughMode = "passthrough-mode"

    case nextTab = "next-tab"
    case previousTab = "previous-tab"

    case splitVertical = "split-vertical"
    case splitHorizontal = "split-horizontal"
    case closePane = "close-pane"
    case focusNextPane = "focus-next-pane"
    case focusPreviousPane = "focus-previous-pane"
}
