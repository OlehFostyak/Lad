/// Lad's own shortcuts: Control-Option plus a key, matched by the physical key so they work in
/// either layout.
public enum Hotkey: Sendable, Equatable, CaseIterable {
    /// ⌃⌥L: automatic switching on or off.
    case toggleAutomatic
    /// ⌃⌥T: the selected Ukrainian text in Latin letters.
    case transliterate
    /// ⌃⌥U: the selected text lowercase → UPPERCASE → Title Case.
    case cycleCase

    public static let modifiers: Modifiers = [.control, .option]

    /// The ANSI key code (kVK_ANSI_*).
    public var keyCode: UInt16 {
        switch self {
        case .toggleAutomatic: 37
        case .transliterate: 17
        case .cycleCase: 32
        }
    }

    /// The shortcut a key press is, if any; Caps Lock does not matter. Key repeats of a held
    /// shortcut match too: they must not reach the app either, though only the first press acts.
    public static func matching(_ event: InputEvent) -> Hotkey? {
        guard case let .keyDown(keyCode, modifiers, _) = event, modifiers.subtracting(.capsLock) == Self.modifiers else {
            return nil
        }
        return allCases.first { $0.keyCode == keyCode }
    }
}
