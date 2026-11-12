import Foundation

enum JSLiteral {
    /// Quotes and escapes a Swift string for safe interpolation into JavaScript.
    static func string(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        // JSONSerialization needs a container, so unwrap the array it produced.
        return String(json.dropFirst().dropLast())
    }
}
