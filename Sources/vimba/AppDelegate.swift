import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var browser: BrowserWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let browser = BrowserWindowController()
        browser.showWindow(nil)
        browser.load(Config.startPage)
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
}
