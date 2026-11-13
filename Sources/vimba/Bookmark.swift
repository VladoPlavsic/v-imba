import Foundation

/// A bookmark addressed by a filesystem-like path, such as
/// `/social/video/youtube.com`.
struct Bookmark: Codable, Equatable {
    var path: String
    var url: String
    var title: String
    var added: Date
}

enum BookmarkPath {
    /// Normalises user input into a canonical path: one leading slash, no
    /// duplicate or trailing separators.
    static func normalize(_ raw: String) -> String {
        let parts = raw
            .trimmingCharacters(in: .whitespaces)
            .split(separator: "/", omittingEmptySubsequences: true)
        return "/" + parts.joined(separator: "/")
    }

    /// The directory portion, so `/a/b/c` yields `/a/b`.
    static func directory(of path: String) -> String {
        var parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return "/" }
        parts.removeLast()
        return parts.isEmpty ? "/" : "/" + parts.joined(separator: "/")
    }

    /// Every directory a path passes through, so `/a/b/c` yields `/a` and `/a/b`.
    static func ancestors(of path: String) -> [String] {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count > 1 else { return [] }
        return (1..<parts.count).map { "/" + parts.prefix($0).joined(separator: "/") }
    }
}
