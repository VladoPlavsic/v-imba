import Foundation

/// All user-visible text resolves through here rather than appearing as a raw
/// literal at the point of use, so the string catalogue stays authoritative.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key)
}
