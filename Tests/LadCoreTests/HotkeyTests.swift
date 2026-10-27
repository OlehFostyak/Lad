import Testing
@testable import LadCore

@Suite("Hotkeys")
struct HotkeyTests {
    private func key(_ keyCode: UInt16, _ modifiers: Modifiers, repeating: Bool = false) -> InputEvent {
        .keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: repeating)
    }

    @Test("Control-Option-L toggles automatic switching, Caps Lock or not")
    func matchesToggle() {
        #expect(Hotkey.matching(key(37, [.control, .option])) == .toggleAutomatic)
        #expect(Hotkey.matching(key(37, [.control, .option, .capsLock])) == .toggleAutomatic)
    }

    @Test("Other modifiers, other keys, repeats and other events are no hotkey")
    func ignoresTheRest() {
        #expect(Hotkey.matching(key(37, [.control])) == nil)
        #expect(Hotkey.matching(key(37, [.control, .option, .shift])) == nil)
        #expect(Hotkey.matching(key(37, [.control, .option, .command])) == nil)
        #expect(Hotkey.matching(key(0, [.control, .option])) == nil)
        #expect(Hotkey.matching(key(37, [.control, .option], repeating: true)) == nil)
        #expect(Hotkey.matching(.modifiersChanged([.control, .option], time: 0)) == nil)
        #expect(Hotkey.matching(.reset) == nil)
    }
}
