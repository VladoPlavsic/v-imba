import AppKit
import Foundation

// WKWebView builds Accept-Language from the app's locale, so this has to be in
// place before WebKit starts if pages are to arrive in English.
UserDefaults.standard.set(Config.contentLanguages, forKey: "AppleLanguages")

let application = NSApplication.shared
let delegate = AppDelegate()

application.delegate = delegate
application.setActivationPolicy(.regular)
MainMenu.install(into: application)
application.activate(ignoringOtherApps: true)
application.run()
