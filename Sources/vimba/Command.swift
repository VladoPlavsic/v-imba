import Foundation

/// An ex command parsed from the command bar.
enum Command: Equatable {
    case open(URL)
    case quit
    /// Stores the current page at a path, e.g. `/social/facebook.com`.
    case saveBookmark(path: String)
    /// Opens the bookmark whose path best matches the query.
    case openBookmark(query: String)
    case deleteBookmark(query: String)
    /// Opens a new buffer, optionally at a target.
    case newTab(target: String)
    /// Switches to the buffer whose name best matches the query.
    case selectBuffer(query: String)
    case closeBuffer(query: String)
    /// Opens the best-matching bookmark in a new buffer.
    case openBookmarkInNewTab(query: String)
    /// Diagnostic: lists stored cookies whose domain matches the filter.
    case cookies(filter: String)
    /// Diagnostic: evaluates an expression in the page and reports the result.
    case evaluate(script: String)
    /// Diagnostic: writes a hint-mode report to ~/.config/vimba/diag.log,
    /// after a delay so a menu can be opened first.
    case diagnose(delay: Double, needle: String)
}

enum CommandParser {
    /// Every command name offered by completion, canonical spellings only.
    static let allNames = [
        "open", "quit", "tabnew", "b", "bd", "sbm", "obm", "tobm", "dbm",
        "cookies", "js", "diag",
    ]

    /// Commands that take a bookmark path, and so offer path completion.
    static let bookmarkSaveNames: Set<String> = ["sbm", "bookmark"]
    static let bookmarkOpenNames: Set<String> = ["obm", "tobm", "dbm"]

    /// Commands that take a buffer name, and so complete against open tabs.
    static let bufferNames: Set<String> = ["b", "buffer", "bd", "bdelete"]

    /// Commands that come in a "here" and a "in a new buffer" form. Shift-Enter
    /// in the command bar swaps one for the other, so a picker can default to
    /// a new buffer and still open in this one on demand.
    private static let alternates: [String: String] = [
        "open": "tabnew", "o": "tabnew", "op": "tabnew",
        "tabnew": "open", "t": "open", "tabopen": "open",
        "obm": "tobm",
        "tobm": "obm", "tbm": "obm",
    ]

    /// The same line aimed at the other buffer, or unchanged when the command
    /// has no counterpart.
    static func swapTarget(_ line: String) -> String {
        let parts = line.trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 1).map(String.init)
        guard let name = parts.first, let other = alternates[name] else { return line }
        return parts.count > 1 ? "\(other) \(parts[1])" : other
    }

    /// Parses a command bar line such as `open example.com` or `sbm /news/bbc`.
    static func parse(_ line: String) -> Command? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let name = parts[0]
        let argument = parts.count > 1 ? parts[1] : ""

        switch name {
        case "o", "op", "open":
            guard let url = URLResolver.resolve(argument) else { return nil }
            return .open(url)
        case "q", "quit":
            return .quit
        case "sbm", "bookmark":
            return .saveBookmark(path: argument)
        case "obm":
            return .openBookmark(query: argument)
        case "tobm", "tbm":
            return .openBookmarkInNewTab(query: argument)
        case "cookies":
            return .cookies(filter: argument)
        case "js":
            return .evaluate(script: argument)
        case "dbm":
            return .deleteBookmark(query: argument)
        case "diag":
            // A leading number is a delay in seconds; the rest is text to
            // locate. `:diag 5 add account` waits, then reports where the
            // words "add account" live.
            var rest = argument
            var delay = 0.0
            let head = rest.split(separator: " ", maxSplits: 1).map(String.init)
            if let first = head.first, let seconds = Double(first) {
                delay = seconds
                rest = head.count > 1 ? head[1] : ""
            }
            return .diagnose(delay: delay, needle: rest)
        case "t", "tabnew", "tabopen":
            return .newTab(target: argument)
        case "b", "buffer":
            return .selectBuffer(query: argument)
        case "bd", "bdelete", "tabclose":
            return .closeBuffer(query: argument)
        default:
            return nil
        }
    }
}

enum URLResolver {
    /// Turns command bar input into a URL, falling back to a search query the
    /// way vimb's `:open` does.
    static func resolve(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }

        let looksLikeHost = !trimmed.contains(" ") && trimmed.contains(".")
        if looksLikeHost, let url = URL(string: "https://\(trimmed)") {
            return url
        }

        var components = URLComponents(string: Config.searchEngine)
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }
}
