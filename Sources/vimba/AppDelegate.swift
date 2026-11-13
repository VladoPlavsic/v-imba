import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var browser: BrowserWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let browser = BrowserWindowController()
        browser.showWindow(nil)
        // Buffers from the last run take precedence over the start page.
        if !browser.restoredSession {
            browser.load(Config.startPage)
        }
        self.browser = browser

        // Activation before the run loop starts is too early to stick: there
        // is no window yet, and the launch may not have granted activation at
        // all. Asking again here, with a window on screen, is what puts the
        // browser in front and gives it the keyboard.
        NSApp.activate()
        browser.window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// A last write on the way out, so a buffer opened seconds before quitting
    /// is still there next time.
    func applicationWillTerminate(_ notification: Notification) {
        browser?.saveSession()
    }
}
