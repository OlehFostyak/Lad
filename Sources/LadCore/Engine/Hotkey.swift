/// Lad's own shortcuts: Control-Option plus a key, matched by the physical key so they work in
/// either layout.
public enum Hotkey: Sendable, Equatable, CaseIterable {
    /// ⌃⌥L: automatic switching on or off.
    case toggleAutomatic

    public static let modifiers: Modifiers = [.control, .option]

    /// The ANSI key code (kVK_ANSI_*).
    public var keyCode: UInt16 {
        switch self {
        case .toggleAutomatic: 37
        }
    }

    /// The shortcut a key press is, if any; Caps Lock does not matter, key repeats do not count.
    public static func matching(_ event: InputEvent) -> Hotkey? {
        guard case let .keyDown(keyCode, modifiers, isRepeat) = event, !isRepeat,
              modifiers.subtracting(.capsLock) == Self.modifiers else { return nil }
        return allCases.first { $0.keyCode == keyCode }
    }
}
