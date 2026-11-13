import Foundation

/// The outcome hints.js reports after init, update or fire.
enum HintStatus {
    case done
    case insert
    case error
    /// Hovering a link or image; carries the target for the status line.
    case over(String)
    /// Yanked content, for the modes that extract rather than follow.
    case data(String)
    case unknown

    init(raw: String) {
        if raw.hasPrefix("DONE:") {
            self = .done
        } else if raw.hasPrefix("INSERT:") {
            self = .insert
        } else if raw.hasPrefix("ERROR:") {
            self = .error
        } else if raw.hasPrefix("OVER:") {
            self = .over(String(raw.dropFirst("OVER:".count)))
        } else if raw.hasPrefix("DATA:") {
            self = .data(String(raw.dropFirst("DATA:".count)))
        } else {
            self = .unknown
        }
    }
}
