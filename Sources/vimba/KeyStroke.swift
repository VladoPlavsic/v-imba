import AppKit

/// A single key press, as a binding refers to it.
///
/// Shift is carried by the character itself (`H` versus `h`). Command chords
/// are never bindable: those belong to AppKit's menu.
struct KeyStroke: Hashable {
    let key: Character
    let control: Bool

    init(key: Character, control: Bool = false) {
        self.key = key
        self.control = control
    }

    init?(event: NSEvent) {
        guard let character = event.charactersIgnoringModifiers?.first else { return nil }
        self.key = character
        self.control = event.modifierFlags.contains(.control)
    }
}

/// Human labels for the key guide.
enum KeyGuide {
    /// Group names follow the kickstart which-key convention, `[S]earch` and
    /// the like, so the letters read the same way they do in his nvim.
    private static let groups: [Character: String] = [
        "s": "[S]earch", "b": "[B]uffer", "g": "[G]o", "w": "[W]indow",
        "y": "[Y]ank", "t": "[T]ab", "z": "[Z]oom", " ": "[ ]Buffers",
    ]

    /// Where turning the action name into words reads badly.
    private static let overrides: [KeyAction: String] = [
        .commandOpen: "open here",
        .commandOpenCurrent: "edit current address",
        .commandMode: "command bar",
        .yankURL: "copy address",
        .yankPath: "copy path",
        .passthroughMode: "pass-through mode",
        .followSelection: "click the selection",
        .scrollTop: "top of page",
        .scrollBottom: "bottom of page",
    ]

    /// What the command bar is prefilled with, named for the guide.
    private static let commandLabels: [String: String] = [
        "b": "buffers", "open": "open here", "tabnew": "new tab",
        "obm": "bookmarks", "tobm": "bookmarks → new tab",
        "sbm": "bookmark this page", "bd": "delete buffer", "dbm": "delete bookmark",
    ]

    static func label(for binding: Binding) -> String {
        switch binding {
        case .action(let action):
            return overrides[action] ?? action.rawValue.replacingOccurrences(of: "-", with: " ")
        case .command(let line):
            let name = line.split(separator: " ").first.map(String.init) ?? line
            return commandLabels[name] ?? ":\(line.trimmingCharacters(in: .whitespaces))"
        }
    }

    static func groupLabel(for stroke: KeyStroke, count: Int) -> String {
        if !stroke.control, let named = groups[Character(stroke.key.lowercased())] {
            return named
        }
        return "+\(count) keys"
    }
}

enum KeyNotation {
    /// Characters standing in for named keys inside a binding.
    private static let named: [String: Character] = [
        "esc": "\u{1B}",
        "cr": "\r",
        "enter": "\r",
        "tab": "\t",
        "bs": "\u{8}",
        "space": " ",
        "lt": "<",
    ]

    /// How a named key is written in the guide.
    private static let display: [Character: String] = [
        " ": "<Space>", "\r": "<CR>", "\t": "<Tab>",
        "\u{1B}": "<Esc>", "\u{8}": "<BS>",
    ]

    /// How a key is written in the guide: the notation it would be bound by.
    static func describe(_ stroke: KeyStroke) -> String {
        if stroke.control {
            return "<C-\(stroke.key)>"
        }
        return display[stroke.key] ?? String(stroke.key)
    }

    /// Parses vim-style notation such as `gg`, `<C-w>v` or `<Esc>` into the
    /// sequence of key presses that triggers it.
    static func parse(_ notation: String) -> [KeyStroke]? {
        var strokes: [KeyStroke] = []
        var rest = Substring(notation)

        while let first = rest.first {
            if first == "<", let close = rest.firstIndex(of: ">") {
                let token = String(rest[rest.index(after: rest.startIndex)..<close])
                guard let stroke = parseToken(token) else { return nil }
                strokes.append(stroke)
                rest = rest[rest.index(after: close)...]
            } else {
                strokes.append(KeyStroke(key: first))
                rest = rest.dropFirst()
            }
        }

        return strokes.isEmpty ? nil : strokes
    }

    private static func parseToken(_ token: String) -> KeyStroke? {
        let lower = token.lowercased()

        if let named = named[lower] {
            return KeyStroke(key: named)
        }

        // <C-x>: control plus a single character.
        if lower.hasPrefix("c-"), token.count == 3, let key = token.last {
            return KeyStroke(key: Character(key.lowercased()), control: true)
        }

        return nil
    }
}
