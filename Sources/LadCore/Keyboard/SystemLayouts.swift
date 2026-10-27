import Carbon

/// Reads and selects keyboard layouts through the Text Input Sources API, which must be called on
/// the main thread.
@MainActor
public enum SystemLayouts {
    /// The keyboard layouts the user can switch to, in the order of the Input menu.
    public static func enabled() -> [LayoutTable] {
        sources(matching: [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String], includeAllInstalled: false)
            .filter(isSelectable)
            .compactMap(table(for:))
    }

    /// An installed layout by input source ID, enabled or not.
    public static func installed(id: String) -> LayoutTable? {
        sources(matching: [kTISPropertyInputSourceID as String: id], includeAllInstalled: true)
            .first
            .flatMap(table(for:))
    }

    /// The ID of the keyboard layout in use (the layout under an input method, if one is active).
    public static func currentID() -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return string(source, kTISPropertyInputSourceID)
    }

    /// Selects an enabled layout; false when it is not enabled or the system refuses.
    @discardableResult
    public static func select(id: String) -> Bool {
        guard let source = sources(matching: [kTISPropertyInputSourceID as String: id], includeAllInstalled: false).first else {
            return false
        }
        return TISSelectInputSource(source) == noErr
    }

    private static func sources(matching properties: [String: String], includeAllInstalled: Bool) -> [TISInputSource] {
        let list = TISCreateInputSourceList(properties as CFDictionary, includeAllInstalled)?.takeRetainedValue()
        return (list as? [TISInputSource]) ?? []
    }

    private static func isSelectable(_ source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else { return false }
        let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }

    private static func table(for source: TISInputSource) -> LayoutTable? {
        guard let id = string(source, kTISPropertyInputSourceID),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        let name = string(source, kTISPropertyLocalizedName) ?? id
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let keyboardType = UInt32(LMGetKbdType())
        var characters: [KeyStroke: String] = [:]
        bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            for keyCode in KeyCode.typingBlock where KeyCode.typesText(keyCode) {
                for stroke in KeyStroke.variants(of: keyCode) {
                    characters[stroke] = translate(stroke, layout: layout, keyboardType: keyboardType)
                }
            }
        }
        return LayoutTable(id: id, name: name, characters: characters)
    }

    private static func translate(_ stroke: KeyStroke, layout: UnsafePointer<UCKeyboardLayout>, keyboardType: UInt32) -> String? {
        var modifiers: UInt32 = 0
        if stroke.shift { modifiers |= UInt32(shiftKey) }
        if stroke.capsLock { modifiers |= UInt32(alphaLock) }
        var deadKeyState: UInt32 = 0
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout, stroke.keyCode, UInt16(kUCKeyActionDown), (modifiers >> 8) & 0xFF, keyboardType,
            OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, buffer.count, &length, &buffer
        )
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: buffer, count: length)
        // Control characters (Return, Escape...) are not text.
        guard text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else { return nil }
        return text
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
