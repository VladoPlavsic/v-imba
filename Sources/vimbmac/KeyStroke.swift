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
