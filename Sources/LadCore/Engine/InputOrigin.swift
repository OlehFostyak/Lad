import Foundation

/// Where an input event came from: the process that posted it (0 for the keyboard itself, as far as
/// macOS reports it) and when it happened, in seconds since startup.
public struct InputOrigin: Sendable, Equatable {
    public let processID: Int64
    public let time: TimeInterval

    public init(processID: Int64, time: TimeInterval) {
        self.processID = processID
        self.time = time
    }
}

/// Tells a program typing for the user (a password manager's auto-type, a text expander) from a
/// person: programs keep pressing keys faster than a hand can for long.
public struct TypingRhythm: Sendable, Equatable {
    /// Programs keep every gap between presses under this, even when they pace their keys...
    public static let machineInterval: TimeInterval = 0.025
    /// ...this many times in a row (five presses), which hands, even rolling over keys, do not.
    public static let machineRun = 4

    private var lastPress: TimeInterval?
    private var quickGaps = 0

    public init() {}

    /// Feeds one key press, at the time the keyboard reported it (not when Lad got to it: presses
    /// queue up while the main thread is busy); true while the presses come at a program's pace.
    public mutating func isMachine(at time: TimeInterval) -> Bool {
        defer { lastPress = time }
        guard let lastPress, time >= lastPress else {
            quickGaps = 0
            return false
        }
        quickGaps = time - lastPress < Self.machineInterval ? quickGaps + 1 : 0
        return quickGaps >= Self.machineRun
    }
}

/// Recognizes key presses another program posted, by the process ID the event carries. The field is
/// trusted only once enough presses came without one (the user's own typing); until then, and on a
/// system that stamps every event, nothing counts as foreign.
public struct SourceFilter: Sendable, Equatable {
    public static let calibrationPresses = 5

    private var unattributedPresses = 0

    public init() {}

    public var isCalibrated: Bool { unattributedPresses >= Self.calibrationPresses }

    public mutating func isForeign(_ origin: InputOrigin) -> Bool {
        guard origin.processID != 0 else {
            unattributedPresses = min(unattributedPresses + 1, Self.calibrationPresses)
            return false
        }
        return isCalibrated
    }
}
