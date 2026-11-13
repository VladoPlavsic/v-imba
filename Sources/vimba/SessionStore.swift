import Foundation

/// The open buffers, remembered across runs in ~/.config/vimba/session.json.
///
/// Only addresses and names are kept, not page state: restoring a buffer
/// reuses the suspension machinery, so a restored buffer costs nothing until
/// it is looked at, and a session of thirty buffers does not load thirty pages
/// at startup.
@MainActor
enum SessionStore {
    struct Entry: Codable {
        let url: String
        let title: String
    }

    private struct Session: Codable {
        let tabs: [Entry]
        let active: Int
    }

    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/vimba/session.json")
    }

    static func load() -> (tabs: [Entry], active: Int) {
        guard Config.restoreSession,
              let data = try? Data(contentsOf: fileURL),
              let session = try? JSONDecoder().decode(Session.self, from: data)
        else {
            return ([], 0)
        }
        return (session.tabs, session.active)
    }

    static func save(_ entries: [Entry], active: Int) {
        guard Config.restoreSession else { return }
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(Session(tabs: entries, active: active)) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}
