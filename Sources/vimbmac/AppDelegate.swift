import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var browser: BrowserWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let browser = BrowserWindowController()
        browser.showWindow(nil)
        browser.load(Config.startPage)
        self.browser = browser
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
