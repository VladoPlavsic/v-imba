import Foundation

/// Input modes, following vimb's model.
enum Mode: Equatable {
    case normal
    case insert
    case command
    case hint
    /// Everything reaches the page, so a site's own shortcuts work.
    case passthrough
}
