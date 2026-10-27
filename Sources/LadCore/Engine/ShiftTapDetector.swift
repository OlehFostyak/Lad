import Foundation

/// Recognizes a double tap of Shift: two short presses of Shift alone, close together, with no
/// other key in between.
public struct ShiftTapDetector: Sendable, Equatable {
    /// A press held longer than this is Shift used for typing, not a tap.
    public static let maxPressDuration: TimeInterval = 0.35
    /// The longest time from the first tap's release to the second's.
    public static let maxInterval: TimeInterval = 0.5

    private var pressedAt: TimeInterval?
    private var lastTapAt: TimeInterval?

    public init() {}

    /// A key press or a click between the taps cancels the double tap.
    public mutating func interrupt() {
        pressedAt = nil
        lastTapAt = nil
    }

    /// Feeds a change of the held modifiers; true when it completes a double tap.
    public mutating func register(_ modifiers: Modifiers, at time: TimeInterval) -> Bool {
        let held = modifiers.subtracting(.capsLock)
        if held == .shift {
            if pressedAt == nil { pressedAt = time }
            return false
        }
        guard held.isEmpty else {
            interrupt()
            return false
        }
        // A release; nil when only Caps Lock toggled or the press was interrupted.
        guard let pressedAt else { return false }
        self.pressedAt = nil
        guard time - pressedAt <= Self.maxPressDuration else {
            lastTapAt = nil
            return false
        }
        if let lastTapAt, time - lastTapAt <= Self.maxInterval {
            self.lastTapAt = nil
            return true
        }
        lastTapAt = time
        return false
    }
}
