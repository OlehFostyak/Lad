/// One key press as Lad records it: the virtual key code and the two modifiers that choose which
/// character the key types. Presses with Command, Control, Option or Fn never become part of a word.
public struct KeyStroke: Hashable, Sendable {
    public let keyCode: UInt16
    public let shift: Bool
    public let capsLock: Bool

    public init(keyCode: UInt16, shift: Bool = false, capsLock: Bool = false) {
        self.keyCode = keyCode
        self.shift = shift
        self.capsLock = capsLock
    }

    /// The four Shift / Caps Lock states of a key, in the order layout snapshots store them.
    static func variants(of keyCode: UInt16) -> [KeyStroke] {
        [
            KeyStroke(keyCode: keyCode),
            KeyStroke(keyCode: keyCode, shift: true),
            KeyStroke(keyCode: keyCode, capsLock: true),
            KeyStroke(keyCode: keyCode, shift: true, capsLock: true),
        ]
    }
}

/// Virtual key codes (ANSI positions) Lad treats specially; the values match Carbon's kVK_* constants.
public enum KeyCode {
    public static let returnKey: UInt16 = 36
    /// Enter on the numeric keypad.
    public static let keypadEnter: UInt16 = 76
    public static let tab: UInt16 = 48
    public static let space: UInt16 = 49
    public static let delete: UInt16 = 51
    public static let c: UInt16 = 8
    public static let v: UInt16 = 9

    /// Letters, digits, punctuation and space. Keys outside the block (arrows, Escape, function
    /// keys, the keypad, Forward Delete...) move the caret or act on the app.
    public static let typingBlock: ClosedRange<UInt16> = 0...50

    /// Whether the key types a layout-dependent character. Return and Tab sit inside the typing
    /// block but act as controls.
    public static func typesText(_ keyCode: UInt16) -> Bool {
        typingBlock.contains(keyCode) && keyCode != returnKey && keyCode != tab
    }
}
