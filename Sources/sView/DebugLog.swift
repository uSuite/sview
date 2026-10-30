import Foundation

/// Prints to stderr when `SVIEW_DEBUG` is set, so scripts can follow what a
/// window shows without Accessibility or Screen Recording permission.
enum DebugLog {
    static let enabled = ProcessInfo.processInfo.environment["SVIEW_DEBUG"] != nil

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else {
            return
        }
        FileHandle.standardError.write(Data((message() + "\n").utf8))
    }
}
