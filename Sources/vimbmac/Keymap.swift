import Foundation

/// Normal-mode bindings, resolved as key sequences so `gg` and `<C-w>v` work
/// the same way vim's do.
///
/// Built-in defaults are overlaid with `~/.config/vimb-mac/keys.json`, so the
/// browser behaves identically with no config file present. Other modes are
/// structural rather than bindable: insert mode passes keys to the page, and
/// command and hint modes are driven by their own editing rules.
struct Keymap {
    private var bindings: [[KeyStroke]: KeyAction]

    /// The action bound to exactly this sequence, if any.
    func action(for sequence: [KeyStroke]) -> KeyAction? {
        bindings[sequence]
    }

    /// Whether any binding starts with this sequence, meaning more keys are
    /// expected rather than the sequence being unknown.
    func hasPrefix(_ sequence: [KeyStroke]) -> Bool {
        bindings.keys.contains { $0.count > sequence.count && Array($0.prefix(sequence.count)) == sequence }
    }

    static let defaultNotation: [String: KeyAction] = [
        "j": .scrollDown,
        "k": .scrollUp,
        "h": .scrollLeft,
        "l": .scrollRight,
        "d": .halfPageDown,
        "u": .halfPageUp,
        "gg": .scrollTop,
        "G": .scrollBottom,
        "H": .back,
        "L": .forward,
        "r": .reload,
        "<C-=>": .zoomIn,
        "<C-->": .zoomOut,
        "<C-0>": .zoomReset,
        "i": .insertMode,
        "f": .hintMode,
        ":": .commandMode,
        "o": .commandOpen,
        "O": .commandOpenCurrent,
        "/": .searchForward,
        "?": .searchBackward,
        "n": .searchNext,
        "N": .searchPrevious,
        "<CR>": .followSelection,
        "<C-z>": .passthroughMode,
        "gt": .nextTab,
        "gT": .previousTab,
        "<C-w>v": .splitVertical,
        "<C-w>s": .splitHorizontal,
        "<C-w>c": .closePane,
        "<C-w>q": .closePane,
        "<C-w>l": .focusNextPane,
        "<C-w>j": .focusNextPane,
        "<C-w>w": .focusNextPane,
        "<C-w>h": .focusPreviousPane,
        "<C-w>k": .focusPreviousPane,
    ]

    /// Defaults, with the user's file layered on top. An entry whose action is
    /// empty or unknown removes the binding, so a default can be switched off.
    static func load() -> Keymap {
        var table: [[KeyStroke]: KeyAction] = [:]
        for (notation, action) in defaultNotation {
            if let sequence = KeyNotation.parse(notation) {
                table[sequence] = action
            }
        }

        for (notation, name) in userBindings() {
            guard let sequence = KeyNotation.parse(notation) else { continue }
            if let action = KeyAction(rawValue: name) {
                table[sequence] = action
            } else {
                table[sequence] = nil
            }
        }

        return Keymap(bindings: table)
    }

    static var configURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: ".config/vimb-mac/keys.json")
    }

    private static func userBindings() -> [String: String] {
        guard let data = try? Data(contentsOf: configURL) else { return [:] }
        guard let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        // Either a flat map, or one nested under "normal".
        return decoded["normal"] ?? [:]
    }
}
