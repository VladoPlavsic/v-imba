import Foundation

/// Normal-mode bindings, resolved as key sequences so `gg` and `<C-w>v` work
/// the same way vim's do.
///
/// Built-in defaults are overlaid with `~/.config/vimba/keys.json`, so the
/// browser behaves identically with no config file present. Other modes are
/// structural rather than bindable: insert mode passes keys to the page, and
/// command and hint modes are driven by their own editing rules.
/// What a key sequence does.
enum Binding: Equatable {
    case action(KeyAction)
    /// Opens the command bar prefilled with this text. The leader pickers are
    /// nothing more than this: `<leader>sb` is `:tobm ` with the cursor left
    /// after it, so the existing fuzzy completion does the searching.
    case command(String)
}

struct Keymap {
    private var bindings: [[KeyStroke]: Binding]
    /// Labels the config gave a binding, overriding the generated one.
    private var labels: [[KeyStroke]: String] = [:]
    /// Group names, keyed by the sequence that reaches the group rather than
    /// by its last key, so `<leader>sb` can read "[B]ookmarks" while a
    /// top-level `b` still reads "[B]uffer".
    private var groupLabels: [[KeyStroke]: String] = [:]

    /// The binding on exactly this sequence, if any.
    func binding(for sequence: [KeyStroke]) -> Binding? {
        bindings[sequence]
    }

    /// The keys that may follow this sequence, for the key guide. A key that
    /// leads to several bindings is reported as a group rather than listing
    /// every leaf under it.
    func continuations(after prefix: [KeyStroke]) -> [KeyGuideEntry] {
        var branches: [KeyStroke: [(sequence: [KeyStroke], binding: Binding)]] = [:]
        for (sequence, binding) in bindings
        where sequence.count > prefix.count && Array(sequence.prefix(prefix.count)) == prefix {
            branches[sequence[prefix.count], default: []].append((sequence, binding))
        }

        return branches.map { stroke, matches in
            let leaves = matches.filter { $0.sequence.count == prefix.count + 1 }
            if matches.count == 1, let only = leaves.first {
                return KeyGuideEntry(
                    key: KeyNotation.describe(stroke),
                    label: labels[only.sequence] ?? KeyGuide.label(for: only.binding),
                    isGroup: false
                )
            }
            return KeyGuideEntry(
                key: KeyNotation.describe(stroke),
                label: groupLabels[prefix + [stroke]]
                    ?? KeyGuide.groupLabel(for: stroke, count: matches.count),
                isGroup: true
            )
        }
        .sorted { ($0.isGroup ? 1 : 0, $0.key.lowercased()) < ($1.isGroup ? 1 : 0, $1.key.lowercased()) }
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
        "y": .yankURL,
        "<leader>yf": .yankURL,
        "<leader>yr": .yankPath,
        "<leader>pe": .commandOpenCurrent,
        "<leader>py": .yankURL,
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

    /// Leader pickers. Each one opens the command bar prefilled, so the
    /// existing fuzzy completion does the searching.
    ///
    /// Tabs sit on `<leader><leader>` because they are what a browser does
    /// most: double-tap the leader, then one key. Everything else is grouped
    /// by what it acts on, with the verbs constant throughout - `o` open
    /// here, `n` open in a new buffer, `d` delete, `s` save or switch.
    static let defaultCommandNotation: [String: String] = [
        "<leader><leader>n": "tabnew ",
        "<leader><leader>s": "b ",
        "<leader><leader>d": "bd ",

        "<leader>bo": "obm ",
        "<leader>bn": "tobm ",
        "<leader>bd": "dbm ",
        "<leader>bs": "sbm /",

        "<leader>po": "open ",
    ]

    /// How the guide names each picker. Without these the label would be
    /// generated from the command, which repeats the group's own name.
    static let defaultLabelNotation: [String: String] = [
        "<leader><leader>n": "new tab",
        "<leader><leader>s": "switch tab",
        "<leader><leader>d": "close tab",

        "<leader>bo": "open here",
        "<leader>bn": "open in new tab",
        "<leader>bd": "delete",
        "<leader>bs": "save this page",

        "<leader>po": "open here",
        "<leader>pe": "edit",
        "<leader>py": "copy full address",
        "<leader>yf": "copy full address",
        "<leader>yr": "copy path only",
    ]

    /// Names for the rows that lead to further keys.
    static let defaultGroupNotation: [String: String] = [
        "<leader><leader>": "[T]abs",
        "<leader>b": "[B]ookmarks",
        "<leader>y": "[Y]ank",
        "<leader>p": "[P]ath",
        "g": "[G]o",
        "<C-w>": "[W]indow",
    ]

    /// The default leader, matching his nvim `mapleader`.
    static let defaultLeader = "<Space>"

    /// Defaults, with the user's file layered on top. An entry whose action is
    /// empty or unknown removes the binding, so a default can be switched off.
    static func load() -> Keymap {
        let config = configDictionary()
        let leader = (config["leader"] as? String) ?? defaultLeader

        var table: [[KeyStroke]: Binding] = [:]
        for (notation, action) in defaultNotation {
            if let sequence = KeyNotation.parse(expand(notation, leader: leader)) {
                table[sequence] = .action(action)
            }
        }
        for (notation, line) in defaultCommandNotation {
            if let sequence = KeyNotation.parse(expand(notation, leader: leader)) {
                table[sequence] = .command(line)
            }
        }

        var groups: [[KeyStroke]: String] = [:]
        for (notation, label) in defaultGroupNotation {
            if let sequence = KeyNotation.parse(expand(notation, leader: leader)) {
                groups[sequence] = label
            }
        }

        var labels: [[KeyStroke]: String] = [:]
        for (notation, label) in defaultLabelNotation {
            if let sequence = KeyNotation.parse(expand(notation, leader: leader)) {
                labels[sequence] = label
            }
        }

        for (notation, value) in userBindings(config) {
            guard let sequence = KeyNotation.parse(expand(notation, leader: leader)) else {
                continue
            }
            // A binding is either a bare string, or an object that can also
            // carry the description the key guide shows.
            var name = value as? String ?? ""
            if let object = value as? [String: String] {
                name = object["action"]
                    ?? object["command"].map { commandPrefix + $0 }
                    ?? ""
                if let description = object["desc"] {
                    labels[sequence] = description
                }
            }

            if name.hasPrefix(commandPrefix) {
                table[sequence] = .command(String(name.dropFirst(commandPrefix.count)))
            } else if let action = KeyAction(rawValue: name) {
                table[sequence] = .action(action)
            } else {
                table[sequence] = nil
                labels[sequence] = nil
            }
        }

        for (notation, label) in (config["groups"] as? [String: String]) ?? [:] {
            if let sequence = KeyNotation.parse(expand(notation, leader: leader)) {
                groups[sequence] = label
            }
        }

        return Keymap(bindings: table, labels: labels, groupLabels: groups)
    }

    /// Marks a config value as a command line to prefill rather than an
    /// action name, e.g. `"<leader>sb": "command:tobm "`.
    private static let commandPrefix = "command:"

    /// Rewrites every `<leader>` into whatever the leader is bound to, so
    /// changing one setting moves every leader binding at once. All of them,
    /// not just the first: `<leader><leader>` is a binding in its own right.
    private static func expand(_ notation: String, leader: String) -> String {
        guard notation.lowercased().contains("<leader>") else { return notation }
        var result = ""
        var rest = Substring(notation)
        while let range = rest.range(of: "<leader>", options: .caseInsensitive) {
            result += rest[rest.startIndex..<range.lowerBound] + leader
            rest = rest[range.upperBound...]
        }
        return result + rest
    }

    static var configURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: ".config/vimba/keys.json")
    }

    private static func configDictionary() -> [String: Any] {
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }

    /// Either a flat map of bindings, or one nested under "normal" beside
    /// settings such as "leader" and "groups". Values stay untyped because a
    /// binding may be a string or an object.
    private static func userBindings(_ config: [String: Any]) -> [String: Any] {
        if let normal = config["normal"] as? [String: Any] {
            return normal
        }
        return config.filter { $0.key != "leader" && $0.key != "groups" }
    }
}
