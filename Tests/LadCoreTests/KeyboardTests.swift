import Foundation
import Testing
@testable import LadCore

@Suite("Layout tables")
struct LayoutTableTests {
    @Test("The fixture has the user's U.S. and Ukrainian-PC layouts")
    func fixtureLayouts() {
        #expect(Fixture.us.script == .latin)
        #expect(Fixture.us.language == .english)
        #expect(Fixture.ua.script == .cyrillic)
        #expect(Fixture.ua.language == .ukrainian)
    }

    @Test("Keys type per layout, Shift and Caps Lock")
    func typesCharacters() {
        #expect(Fixture.us.text(for: KeyStroke(keyCode: 5)) == "g")
        #expect(Fixture.us.text(for: KeyStroke(keyCode: 5, shift: true)) == "G")
        #expect(Fixture.ua.text(for: KeyStroke(keyCode: 5)) == "п")
        #expect(Fixture.ua.text(for: KeyStroke(keyCode: 5, capsLock: true)) == "П")
        #expect(Fixture.ua.text(for: KeyStroke(keyCode: 50)) == "'")
        #expect(Fixture.ua.text(for: KeyStroke(keyCode: 42)) == "ґ")
        #expect(Fixture.us.text(for: KeyStroke(keyCode: KeyCode.returnKey)) == nil)
    }

    @Test("The simplest stroke types a character")
    func findsStrokes() {
        #expect(Fixture.us.stroke(for: "G") == KeyStroke(keyCode: 5, shift: true))
        #expect(Fixture.us.stroke(for: "g") == KeyStroke(keyCode: 5))
        #expect(Fixture.ua.stroke(for: "'") == KeyStroke(keyCode: 50))
        #expect(Fixture.us.stroke(for: "п") == nil)
    }

    @Test("A sequence types nothing when one key types nothing")
    func sequenceWithGap() {
        let table = LayoutTable(id: "t", name: "t", characters: [KeyStroke(keyCode: 0): "a"])
        #expect(table.text(for: [KeyStroke(keyCode: 0), KeyStroke(keyCode: 0)]) == "aa")
        #expect(table.text(for: [KeyStroke(keyCode: 0), KeyStroke(keyCode: 1)]) == nil)
        #expect(table.script == .other)
        #expect(table.language == nil)
    }

    @Test("Snapshots round-trip")
    func roundTrips() throws {
        #expect(LayoutTable(snapshot: Fixture.us.snapshot) == Fixture.us)
        let data = try JSONEncoder().encode(Fixture.ua.snapshot)
        #expect(LayoutTable(snapshot: try JSONDecoder().decode(LayoutSnapshot.self, from: data)) == Fixture.ua)
    }

    @Test("Pairs need two languages")
    func pairs() {
        #expect(LayoutPair(current: Fixture.us, other: Fixture.us) == nil)
        let pair = LayoutPair.choose(currentID: Fixture.ua.id, from: [Fixture.ua, Fixture.us])
        #expect(pair?.current == Fixture.ua)
        #expect(pair?.other == Fixture.us)
        #expect(pair?.swapped.current == Fixture.us)
        #expect(LayoutPair.choose(currentID: "missing", from: Fixture.tables) == nil)
    }

    @Test("Only the typing block types text")
    func typingBlock() {
        #expect(KeyCode.typesText(0))
        #expect(KeyCode.typesText(KeyCode.space))
        #expect(!KeyCode.typesText(KeyCode.returnKey))
        #expect(!KeyCode.typesText(KeyCode.tab))
        #expect(!KeyCode.typesText(KeyCode.delete))
        #expect(!KeyCode.typesText(123))
    }

    @Test("The system's U.S. layout builds the same table") @MainActor
    func systemLayout() throws {
        let us = try #require(SystemLayouts.installed(id: "com.apple.keylayout.US"))
        #expect(us.text(for: KeyStroke(keyCode: 0)) == "a")
        #expect(us.script == .latin)
        #expect(us.snapshot.keys == Fixture.us.snapshot.keys)
    }
}

@Suite("Text conversion")
struct TextConverterTests {
    @Test("Latin text converts to the Ukrainian layout")
    func convertsLatin() {
        let converted = TextConverter.convert("Ghbdsn, zr cghfdb? 123", layouts: Fixture.typingInUS)
        #expect(converted == ConvertedText(text: "Привітб як справи, 123", layoutID: Fixture.ua.id))
    }

    @Test("Cyrillic text converts to the U.S. layout, whichever layout is current")
    func convertsCyrillic() {
        let converted = TextConverter.convert("Руддщ цщкдв", layouts: Fixture.typingInUS)
        #expect(converted == ConvertedText(text: "Hello world", layoutID: Fixture.us.id))
    }

    @Test("Text without letters does not convert")
    func skipsWithoutLetters() {
        #expect(TextConverter.convert("123 !?", layouts: Fixture.typingInUS) == nil)
    }

    @Test("Characters neither layout types stay")
    func keepsUnknownCharacters() {
        #expect(TextConverter.convert("ghbdsn\n😀", layouts: Fixture.typingInUS)?.text == "привіт\n😀")
    }
}

@Suite("Double Shift")
struct ShiftTapDetectorTests {
    private func taps(_ events: [(Modifiers, Double)]) -> [Bool] {
        var detector = ShiftTapDetector()
        return events.map { detector.register($0.0, at: $0.1) }
    }

    @Test("Two quick taps fire on the second release")
    func doubleTap() {
        #expect(taps([(.shift, 0), ([], 0.05), (.shift, 0.2), ([], 0.25)]) == [false, false, false, true])
    }

    @Test("Slow, long or combined presses do not fire")
    func noFire() {
        #expect(taps([(.shift, 0), ([], 0.05), (.shift, 1.0), ([], 1.05)]).last == false)
        #expect(taps([(.shift, 0), ([], 0.5), (.shift, 0.6), ([], 0.65)]).last == false)
        #expect(taps([(.shift, 0), ([], 0.05), ([.shift, .command], 0.1), ([], 0.15), (.shift, 0.2), ([], 0.25)]).last == false)
    }

    @Test("Caps Lock does not break a double tap; an interruption does")
    func capsLockAndInterruptions() {
        #expect(taps([(.shift, 0), ([], 0.05), (.capsLock, 0.1), (.shift, 0.2), ([], 0.25)]).last == true)
        var detector = ShiftTapDetector()
        _ = detector.register(.shift, at: 0)
        _ = detector.register([], at: 0.05)
        detector.interrupt()
        _ = detector.register(.shift, at: 0.1)
        let fired = detector.register([], at: 0.15)
        #expect(!fired)
    }
}
