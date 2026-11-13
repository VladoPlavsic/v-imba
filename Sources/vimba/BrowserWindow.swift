import AppKit

/// The browser window, with no title bar: the page and the status line are the
/// whole window.
///
/// A borderless window refuses to become key or main by default, which would
/// leave the keyboard dead, so both are overridden. Resizing still works
/// because `.resizable` stays in the style mask and AppKit keeps the hit areas
/// at the window's edges; there is simply nothing left to drag it by, which is
/// the trade for having no chrome. `window-chrome: "titled"` in config.json
/// puts the title bar back.
final class BrowserWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
