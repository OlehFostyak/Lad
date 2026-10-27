import os

/// Everything Lad ever logs (`make logs`). Only these fixed events exist, so typed text cannot
/// reach the log; the lint tests allow Logger and privacy markers in this file alone.
enum LogEvent {
    case tapInstalled
    case tapReenabled
    /// Layout IDs are system identifiers, not typed text.
    case layoutNotSelected(id: String)
    case wordListsFailed
    case loginItemFailed
    case anotherInstanceRunning
}

enum Log {
    private nonisolated static let logger = Logger(subsystem: "dev.oleh.lad", category: "app")

    nonisolated static func record(_ event: LogEvent) {
        switch event {
        case .tapInstalled: logger.info("event tap installed")
        case .tapReenabled: logger.notice("event tap re-enabled")
        case let .layoutNotSelected(id): logger.error("could not select layout \(id, privacy: .public)")
        case .wordListsFailed: logger.error("word lists failed to load")
        case .loginItemFailed: logger.error("login item change failed")
        case .anotherInstanceRunning: logger.notice("another Lad is running; quitting")
        }
    }
}
