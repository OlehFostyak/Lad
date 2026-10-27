import Testing
@testable import LadCore

@Suite("Case fixes")
struct CaseFixTests {
    @Test("Two initial capitals become one", arguments: [
        ("ПРивіт", Language.ukrainian, "Привіт"), ("HEllo", .english, "Hello"), ("HEllo,", .english, "Hello,"),
        ("ДЯкую!", .ukrainian, "Дякую!"), ("М'Ята", .ukrainian, "М'ята"),
    ])
    func fixesTwoCapitals(text: String, language: Language, fixed: String) {
        #expect(CaseFix.twoInitialCapitals(text, in: language) == fixed)
    }

    @Test("Other shapes stay", arguments: ["IDs", "ABCd", "Hello", "hello", "HELLO", "HeLlo", "OK", "A", ""])
    func leavesOtherShapes(text: String) {
        #expect(CaseFix.twoInitialCapitals(text, in: .english) == nil)
    }
}

@Suite("Engine case fixes")
struct EngineCaseFixTests {
    private let us = Fixture.us
    private let ua = Fixture.ua

    @Test("ПРивіт becomes Привіт at the space, in the same layout")
    func fixesAtSpace() throws {
        var typist = Typist(Fixture.typingInUA)
        let output = try #require(typist.type("ПРивіт ", on: ua).last)
        #expect(output.suppressesEvent)
        #expect(output.replacement == Replacement(deleteCount: 6, text: "Привіт ", layoutID: ua.id))
        #expect(typist.engine.layouts?.current.id == ua.id)
    }

    @Test("English too, but not words that are not listed once fixed")
    func checksTheWordList() {
        var english = Typist(Fixture.typingInUS)
        #expect(english.type("HEllo ", on: us).last?.replacement?.text == "Hello ")
        var brand = Typist(Fixture.typingInUS)
        #expect(brand.type("VMware IDs ", on: us).isEmpty)
    }

    @Test("Double Shift turns the fix back and remembers the word")
    func undoesFix() {
        var typist = Typist(Fixture.typingInUA)
        typist.type("ПРивіт ", on: ua)
        let undo = typist.doubleShift()
        #expect(undo.replacement == Replacement(deleteCount: 7, text: "ПРивіт ", layoutID: ua.id))
        #expect(undo.learnedException == "привіт")
        #expect(typist.engine.layouts?.current.id == ua.id)
        #expect(typist.type("ПРивіт ", on: ua).isEmpty)
    }

    @Test("The fix happens at Return too, and can be switched off")
    func fixesAtReturnAndSwitchesOff() {
        var typist = Typist(Fixture.typingInUA)
        typist.type("ПРивіт", on: ua)
        #expect(typist.pressReturn().replacement == Replacement(
            deleteCount: 6, text: "Привіт", layoutID: ua.id, followUpKey: KeyStroke(keyCode: KeyCode.returnKey)
        ))
        var off = Typist(Fixture.typingInUA)
        off.engine.fixesTwoCapitals = false
        #expect(off.type("ПРивіт ", on: ua).isEmpty)
    }
}
