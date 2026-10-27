import Foundation

/// Where an input event came from: the process that posted it (0 for the keyboard itself, as far as
/// macOS reports it) and when Lad saw it, in seconds on a monotonic clock.
public struct InputOrigin: Sendable, Equatable {
    public let processID: Int64
    public let time: TimeInterval

    public init(processID: Int64, time: TimeInterval) {
        self.processID = processID
        self.time = time
    }
}

/// Tells a program typing for the user (a password manager's auto-type, a text expander) from a
/// person: programs post key presses faster than any hand.
public struct TypingRhythm: Sendable, Equatable {
    /// Two presses closer than this are not a person's.
    public static let machineInterval: TimeInterval = 0.008
    /// This many such quick gaps in a row make a program's burst (three presses).
    public static let burstLength = 2

    private var lastPress: TimeInterval?
    private var quickGaps = 0

    public init() {}

    /// Feeds one key press; true from the third press of a machine-speed burst on.
    public mutating func isMachine(at time: TimeInterval) -> Bool {
        defer { lastPress = time }
        guard let lastPress, time >= lastPress, time - lastPress < Self.machineInterval else {
            quickGaps = 0
            return false
        }
        quickGaps += 1
        return quickGaps >= Self.burstLength
    }
}

/// Recognizes key presses another program posted, by the process ID the event carries. The field is
/// trusted only once enough presses came without one (the user's own typing); until then, and on a
/// system that stamps every event, nothing counts as foreign.
public struct SourceFilter: Sendable, Equatable {
    public static let calibrationPresses = 20

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
