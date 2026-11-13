import Foundation

/// The command lines submitted so far, newest last, persisted across runs.
///
/// Exists so a mistyped address costs a keystroke rather than retyping it:
/// `Ctrl-p` walks back through what was typed before, matching whatever is
/// already on the line.
@MainActor
final class CommandHistory {
    private var entries: [String] = []
    /// Where in `entries` recall currently sits, counted from the end.
    private var cursor: Int?
    /// The line as the user typed it, kept so walking past the newest entry
    /// restores it rather than leaving their text lost.
    private var draft = ""
    /// What recall matches against, fixed when recall starts.
    private var prefix = ""

    private let limit = 500

    private var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/vimba/history")
    }

    init() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        entries = text.split(separator: "\n").map(String.init)
    }

    /// Records a submitted line. A repeat of the newest entry is not stored
    /// twice, the way shell history behaves.
    func record(_ line: String) {
        reset()
        let line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, entries.last != line else { return }
        entries.append(line)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        save()
    }

    /// Call when the command bar opens or closes, so the next recall starts
    /// from the newest entry again.
    func reset() {
        cursor = nil
        draft = ""
        prefix = ""
    }

    /// The previous matching entry, or nil when there is nothing older.
    func previous(startingFrom current: String) -> String? {
        if cursor == nil {
            draft = current
            prefix = current
        }
        let start = cursor ?? entries.count
        guard start > 0 else { return nil }
        for index in stride(from: start - 1, through: 0, by: -1)
        where prefix.isEmpty || entries[index].hasPrefix(prefix) {
            cursor = index
            return entries[index]
        }
        return nil
    }

    /// The next matching entry, ending at the line the user had typed.
    func next() -> String? {
        guard let start = cursor else { return nil }
        for index in stride(from: start + 1, to: entries.count, by: 1)
        where prefix.isEmpty || entries[index].hasPrefix(prefix) {
            cursor = index
            return entries[index]
        }
        cursor = nil
        return draft
    }

    private func save() {
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? entries.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
