import Foundation

/// Diagnostics on stderr, enabled with VIMBA_DEBUG=1 so they can stay in place
/// without noise in normal use.
enum Log {
    static let enabled = ProcessInfo.processInfo.environment["VIMBA_DEBUG"] == "1"

    static func debug(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data((message() + "\n").utf8))
    }
}
