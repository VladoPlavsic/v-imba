import Foundation

/// Settings, with the built-in value used unless `~/.config/vimba/config.json`
/// overrides it. See `config.example.json` for the key names.
enum Config {
    static let startPage = Settings.url("start-page", URL(string: "https://duckduckgo.com")!)
    static let searchEngine = Settings.string("search-engine", "https://duckduckgo.com/")
    static let windowSize = CGSize(
        width: Settings.double("window-width", 1280),
        height: Settings.double("window-height", 800)
    )

    /// "none" for a window with no title bar at all, "titled" to put the
    /// close, minimise and zoom buttons back.
    static let windowChrome = Settings.string("window-chrome", "none")

    /// Pixels moved by a single `j` or `k`.
    static let scrollStep = Settings.int("scroll-step", 60)

    /// Characters used to label hints. The home row by default: a letter is
    /// found by muscle memory where a digit needs looking down at. Any key
    /// *not* in this set filters hints by their text instead, so the wider
    /// this is, the shorter the labels and the less text filtering is left.
    static let hintKeys = Settings.string("hint-keys", "asdfghjkl")
    static let maxHints = Settings.int("max-hints", 500)

    /// Multiplier applied per zoom step, and the range it is clamped to.
    static let zoomStep = CGFloat(Settings.double("zoom-step", 1.1))
    static let zoomRange: ClosedRange<CGFloat> =
        CGFloat(Settings.double("zoom-min", 0.3))...CGFloat(Settings.double("zoom-max", 5.0))

    /// Sent as Accept-Language, so sites serve English rather than following
    /// the system locale.
    static let contentLanguages = Settings.strings("content-languages", ["en-US", "en"])

    /// Appended to WebKit's user agent. Without a recognised browser token
    /// Google treats the client as an embedded web view and invalidates
    /// sessions, which is why YouTube logs out while other sites do not.
    static let userAgentSuffix = Settings.string(
        "user-agent-suffix", "Version/18.0 Safari/605.1.15"
    )

    /// Whether the open buffers come back on the next run.
    static let restoreSession = Settings.bool("restore-session", true)

    /// How long a background tab may sit idle before it is suspended.
    static let tabIdleTimeout = Settings.double("tab-idle-minutes", 30) * 60
}
