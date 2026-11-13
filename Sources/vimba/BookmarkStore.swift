import Foundation

/// Bookmarks persisted as JSON under ~/.config/vimba/.
@MainActor
final class BookmarkStore {
    private(set) var bookmarks: [Bookmark] = []

    private let fileURL: URL

    init() {
        let directory = FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: ".config/vimba", directoryHint: .isDirectory)
        fileURL = directory.appending(path: "bookmarks.json")
        load()
    }

    /// Replaces any bookmark already at this path.
    func add(path: String, url: String, title: String) {
        let canonical = BookmarkPath.normalize(path)
        bookmarks.removeAll { $0.path == canonical }
        bookmarks.append(
            Bookmark(path: canonical, url: url, title: title, added: Date())
        )
        bookmarks.sort { $0.path < $1.path }
        save()
    }

    @discardableResult
    func remove(path: String) -> Bool {
        let canonical = BookmarkPath.normalize(path)
        let before = bookmarks.count
        bookmarks.removeAll { $0.path == canonical }
        if bookmarks.count != before {
            save()
            return true
        }
        return false
    }

    func bookmark(at path: String) -> Bookmark? {
        bookmarks.first { $0.path == BookmarkPath.normalize(path) }
    }

    var paths: [String] {
        bookmarks.map(\.path)
    }

    /// Every directory any bookmark lives in, each with a trailing slash so
    /// completing one invites another segment.
    var directories: [String] {
        let all = bookmarks.flatMap { BookmarkPath.ancestors(of: $0.path) }
        return Set(all).sorted().map { $0 + "/" }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        bookmarks = (try? decoder.decode([Bookmark].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(bookmarks) else { return }

        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
