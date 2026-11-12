import Foundation

/// Settings that will move into a user config file once `:set` exists.
enum Config {
    static let startPage = URL(string: "https://duckduckgo.com")!
    static let searchEngine = "https://duckduckgo.com/"
    static let windowSize = CGSize(width: 1280, height: 800)

    /// Pixels moved by a single `j` or `k`.
    static let scrollStep = 60

    /// Characters used to label hints, matching vimb's SETTING_HINT_KEYS.
    static let hintKeys = "0123456789"
    static let maxHints = 500

    /// Multiplier applied per zoom step, and the range it is clamped to.
    static let zoomStep: CGFloat = 1.1
    static let zoomRange: ClosedRange<CGFloat> = 0.3...5.0

    /// Sent as Accept-Language, so sites serve English rather than following
    /// the system locale.
    static let contentLanguages = ["en-US", "en"]

    /// Appended to WebKit's user agent. Without a recognised browser token
    /// Google treats the client as an embedded web view and invalidates
    /// sessions, which is why YouTube logs out while other sites do not.
    static let userAgentSuffix = "Version/18.0 Safari/605.1.15"

    /// How long a background tab may sit idle before it is suspended.
    static let tabIdleTimeout: TimeInterval = 30 * 60
}
