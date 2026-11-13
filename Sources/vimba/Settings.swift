import Foundation

/// Values read from `~/.config/vimba/config.json`, so the things that used to
/// be compile-time constants can be changed without a rebuild.
///
/// Read once, at first use: a reload would have to reach the web views'
/// configuration, which WebKit fixes when they are created.
enum Settings {
    /// `nonisolated(unsafe)` because `[String: Any]` is not Sendable. It is
    /// written once, by this initialiser, and only read afterwards.
    nonisolated(unsafe) private static let values: [String: Any] = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/vimba/config.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }()

    static func string(_ key: String, _ fallback: String) -> String {
        values[key] as? String ?? fallback
    }

    static func url(_ key: String, _ fallback: URL) -> URL {
        guard let text = values[key] as? String, let url = URL(string: text) else {
            return fallback
        }
        return url
    }

    static func int(_ key: String, _ fallback: Int) -> Int {
        (values[key] as? NSNumber)?.intValue ?? fallback
    }

    static func double(_ key: String, _ fallback: Double) -> Double {
        (values[key] as? NSNumber)?.doubleValue ?? fallback
    }

    static func strings(_ key: String, _ fallback: [String]) -> [String] {
        values[key] as? [String] ?? fallback
    }

    /// Extra CSS appended after the built-in hint stylesheet, so hint colours
    /// and sizes can be restyled without touching the bundle.
    static var userHintCSS: String {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/vimba/hints.css")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
