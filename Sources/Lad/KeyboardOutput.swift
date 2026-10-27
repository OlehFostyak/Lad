import CoreGraphics
import LadCore

/// Types for Lad: Backspaces, text and shortcuts as synthetic key events, stamped with a marker so
/// Lad's own event tap lets them through untouched.
final class KeyboardOutput {
    /// The eventSourceUserData of every event Lad posts ("Lad" in ASCII).
    nonisolated static let marker: Int64 = 0x4C_61_64
    /// CGEventKeyboardSetUnicodeString takes at most 20 UTF-16 units per event.
    private static let chunkLength = 16

    private let source: CGEventSource?

    init() {
        // A private state: the user's held modifiers never leak into Lad's events.
        source = CGEventSource(stateID: .privateState)
        source?.userData = Self.marker
        // Posting must not mute the user's own keys for the default quarter second.
        source?.localEventsSuppressionInterval = 0
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
    }

    func perform(_ replacement: Replacement) {
        for _ in 0..<replacement.deleteCount {
            press(KeyCode.delete)
        }
        type(replacement.text)
        if let key = replacement.followUpKey {
            press(key.keyCode, flags: key.shift ? .maskShift : [])
        }
    }

    func press(_ keyCode: UInt16, flags: CGEventFlags = []) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    func type(_ text: String) {
        for chunk in Self.chunks(of: text) {
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// UTF-16 chunks that never split a character.
    private static func chunks(of text: String) -> [[UniChar]] {
        var chunks: [[UniChar]] = []
        var current: [UniChar] = []
        for character in text {
            let units = Array(String(character).utf16)
            if current.count + units.count > chunkLength, !current.isEmpty {
                chunks.append(current)
                current = []
            }
            current += units
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}
