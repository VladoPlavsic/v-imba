import Foundation

/// Writes diagnostic reports to ~/.config/vimba/diag.log.
///
/// A file rather than stderr: the app is normally started from Finder, where
/// stderr goes nowhere, and a hint-mode trace is far too long for the status
/// line.
enum Diagnostics {
    /// Set by `:diag trace`. Off by default because it logs on every keystroke
    /// of a hint session.
    nonisolated(unsafe) static var traceHints = false

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/vimba/diag.log")
    }

    static func append(_ text: String) {
        let url = logURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        FileHandle.standardError.write(data)
    }

    static func trace(_ text: String) {
        guard traceHints else { return }
        append("[hint] \(text)\n")
    }
}
