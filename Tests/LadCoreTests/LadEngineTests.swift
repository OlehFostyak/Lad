import Testing
@testable import LadCore

@Suite("Engine")
struct LadEngineTests {
    private let us = Fixture.us
    private let ua = Fixture.ua

    @Test("A Ukrainian word typed in the U.S. layout converts at the space")
    func convertsUkrainianTypedInUS() throws {
        var typist = Typist(Fixture.typingInUS)
        let output = try #require(typist.type("ghbdsn ", on: us).last)
        #expect(output.suppressesEvent)
        #expect(output.replacement == Replacement(deleteCount: 6, text: "привіт ", layoutID: ua.id))
        #expect(typist.engine.layouts?.current.id == ua.id)
    }

    @Test("An English word typed in the Ukrainian layout converts at the space")
    func convertsEnglishTypedInUA() throws {
        var typist = Typist(Fixture.typingInUA)
        let output = try #require(typist.type("руддщ ", on: ua).last)
        #expect(output.replacement == Replacement(deleteCount: 5, text: "hello ", layoutID: us.id))
    }

    @Test("Words that fit their layout stay")
    func keepsFittingWords() {
        var english = Typist(Fixture.typingInUS)
        #expect(english.type("hello world, this is git ", on: us).isEmpty)
        var ukrainian = Typist(Fixture.typingInUA)
        #expect(ukrainian.type("привіт, як справи ", on: ua).isEmpty)
    }

    @Test("The case of each key is kept")
    func keepsCase() throws {
        var typist = Typist(Fixture.typingInUS)
        let output = try #require(typist.type("Ghbdsn ", on: us).last)
        #expect(output.replacement?.text == "Привіт ")
    }

    @Test("Punctuation after a word waits for the space, then both convert")
    func convertsAcrossPunctuation() throws {
        var typist = Typist(Fixture.typingInUS)
        let outputs = typist.type("ghbdsn? zr ", on: us)
        let output = try #require(outputs.last)
        #expect(outputs.count == 1)
        #expect(output.replacement == Replacement(deleteCount: 10, text: "привіт, як ", layoutID: ua.id))
    }

    @Test("Paths and hyphenated code are left alone")
    func leavesPathsAlone() {
        var typist = Typist(Fixture.typingInUS)
        #expect(typist.type("src/main jwt-token ", on: us).isEmpty)
    }

    @Test("A pending one-letter word converts along with the next word")
    func convertsPendingLetter() throws {
        var typist = Typist(Fixture.typingInUS)
        let output = try #require(typist.type("z [jxe ", on: us).last)
        #expect(output.replacement == Replacement(deleteCount: 6, text: "я хочу ", layoutID: ua.id))
    }

    @Test("A one-letter English word does not convert along")
    func keepsEnglishLetter() throws {
        var typist = Typist(Fixture.typingInUS)
        let output = try #require(typist.type("a ghbdsn ", on: us).last)
        #expect(output.replacement == Replacement(deleteCount: 6, text: "привіт ", layoutID: ua.id))
    }

    @Test("A code token converts only along with a following word")
    func convertsCodeTokenAlong() throws {
        var typist = Typist(Fixture.typingInUS)
        #expect(typist.type("db ", on: us).isEmpty)
        let output = try #require(typist.type("pyf'nt ", on: us).last)
        #expect(output.replacement == Replacement(deleteCount: 9, text: "ви знаєте ", layoutID: ua.id))
    }

    @Test("Double Shift right after a conversion turns it back and learns the word")
    func undoesConversion() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("ghbdsn ", on: us)
        let output = typist.doubleShift()
        #expect(output.replacement == Replacement(deleteCount: 7, text: "ghbdsn ", layoutID: us.id))
        #expect(output.learnedException == "ghbdsn")
        #expect(typist.engine.layouts?.current.id == us.id)
        #expect(typist.type("ghbdsn ", on: us).isEmpty)
    }

    @Test("Double Shift converts the word being typed")
    func convertsCurrentWordByHand() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("ghbd", on: us)
        #expect(typist.doubleShift().replacement == Replacement(deleteCount: 4, text: "прив", layoutID: ua.id))
        #expect(typist.engine.layouts?.current.id == ua.id)
    }

    @Test("Double Shift converts the last word when automatic switching is off")
    func convertsLastWordByHand() {
        var typist = Typist(Fixture.typingInUS, automatic: false)
        #expect(typist.type("ghbdsn ", on: us).isEmpty)
        #expect(typist.doubleShift().replacement == Replacement(deleteCount: 7, text: "привіт ", layoutID: ua.id))
    }

    @Test("Double Shift twice turns a manual conversion back")
    func togglesManualConversion() {
        var typist = Typist(Fixture.typingInUS, automatic: false)
        typist.type("ghbd", on: us)
        _ = typist.doubleShift()
        let output = typist.doubleShift()
        #expect(output.replacement == Replacement(deleteCount: 4, text: "ghbd", layoutID: us.id))
        #expect(output.learnedException == nil)
    }

    @Test("Double Shift with nothing typed converts the selection")
    func convertsSelection() {
        var typist = Typist(Fixture.typingInUS)
        #expect(typist.doubleShift().convertsSelection)
    }

    @Test("Shortcuts and clicks forget the word")
    func forgetsOnShortcutsAndClicks() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("ghbd", on: us)
        typist.press(KeyCode.c, .command)
        #expect(typist.doubleShift().convertsSelection)
        typist.type("ghbd", on: us)
        _ = typist.engine.handle(.reset)
        #expect(typist.doubleShift().convertsSelection)
    }

    @Test("Backspace edits the word")
    func editsWithBackspace() throws {
        var typist = Typist(Fixture.typingInUS)
        typist.type("ghbdsx", on: us)
        typist.press(KeyCode.delete)
        let output = try #require(typist.type("n ", on: us).last)
        #expect(output.replacement == Replacement(deleteCount: 6, text: "привіт ", layoutID: ua.id))
    }

    @Test("Deleting the space puts the caret back into the word")
    func backspaceReopensWord() {
        var typist = Typist(Fixture.typingInUS, automatic: false)
        typist.type("ghbd ", on: us)
        typist.press(KeyCode.delete)
        typist.type("sn", on: us)
        #expect(typist.doubleShift().replacement == Replacement(deleteCount: 6, text: "привіт", layoutID: ua.id))
    }

    @Test("Runs longer than a word are ignored")
    func ignoresLongRuns() {
        var typist = Typist(Fixture.typingInUS)
        #expect(typist.type(String(repeating: "g", count: LadEngine.maxWordLength + 1) + " ", on: us).isEmpty)
        #expect(typist.doubleShift().convertsSelection)
    }

    @Test("Lad's own layout switch is not a reset")
    func ownSwitchKeepsState() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("ghbdsn ", on: us)
        typist.engine.currentLayoutDidChange(to: ua.id)
        #expect(typist.doubleShift().replacement?.text == "ghbdsn ")
    }

    @Test("A layout switch by hand swaps the pair and forgets the word")
    func manualSwitchSwapsPair() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("ghbd", on: us)
        typist.engine.currentLayoutDidChange(to: ua.id)
        #expect(typist.engine.layouts?.current.id == ua.id)
        #expect(typist.doubleShift().convertsSelection)
    }

    @Test("Exceptions never convert")
    func respectsExceptions() {
        var typist = Typist(Fixture.typingInUS)
        typist.engine.exceptions = ["ghbdsn"]
        #expect(typist.type("ghbdsn ", on: us).isEmpty)
    }

    @Test("Key repeats and keys outside the typing block forget the word")
    func forgetsOnRepeatAndControls() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("ghbd", on: us)
        _ = typist.engine.handle(.keyDown(keyCode: 1, modifiers: [], isRepeat: true))
        #expect(typist.doubleShift().convertsSelection)
        typist.type("ghbd", on: us)
        typist.press(123)
        #expect(typist.doubleShift().convertsSelection)
    }

    @Test("A word converts at Return, which is pressed again after the retyped word")
    func convertsAtReturn() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("ghbdsn", on: us)
        let output = typist.pressReturn()
        #expect(output.suppressesEvent)
        #expect(output.replacement == Replacement(
            deleteCount: 6, text: "привіт", layoutID: ua.id, followUpKey: KeyStroke(keyCode: KeyCode.returnKey)
        ))
        // The line may be sent already: there is nothing to undo.
        #expect(typist.doubleShift().convertsSelection)
    }

    @Test("Shift+Return keeps its Shift, keypad Enter its key")
    func keepsReturnModifiers() {
        var shifted = Typist(Fixture.typingInUS)
        shifted.type("ghbdsn", on: us)
        #expect(shifted.pressReturn(.shift).replacement?.followUpKey == KeyStroke(keyCode: KeyCode.returnKey, shift: true))
        var keypad = Typist(Fixture.typingInUS)
        keypad.type("ghbdsn", on: us)
        #expect(keypad.press(KeyCode.keypadEnter).replacement?.followUpKey == KeyStroke(keyCode: KeyCode.keypadEnter))
    }

    @Test("Return passes when the word fits, when switched off, or as a shortcut")
    func passesReturn() {
        var fitting = Typist(Fixture.typingInUS)
        fitting.type("hello", on: us)
        #expect(fitting.pressReturn() == .pass)
        var off = Typist(Fixture.typingInUS)
        off.engine.convertsOnReturn = false
        off.type("ghbdsn", on: us)
        #expect(off.pressReturn() == .pass)
        var shortcut = Typist(Fixture.typingInUS)
        shortcut.type("ghbdsn", on: us)
        #expect(shortcut.pressReturn(.command) == .pass)
    }

    @Test("Pending words convert along at Return")
    func convertsPendingAtReturn() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("z [jxe", on: us)
        #expect(typist.pressReturn().replacement == Replacement(
            deleteCount: 6, text: "я хочу", layoutID: ua.id, followUpKey: KeyStroke(keyCode: KeyCode.returnKey)
        ))
    }

    @Test("A word fixed by hand is learned and converts on its own next time")
    func learnsFromFixByHand() throws {
        var typist = Typist(Fixture.typingInUS)
        #expect(typist.type("db ", on: us).isEmpty)
        let fix = typist.doubleShift()
        #expect(fix.replacement?.text == "ви ")
        #expect(fix.learnedWord == "db")
        #expect(typist.engine.learnedWords == ["db"])
        typist.engine.currentLayoutDidChange(to: us.id)
        let output = try #require(typist.type("db ", on: us).last)
        #expect(output.replacement == Replacement(deleteCount: 2, text: "ви ", layoutID: ua.id))
    }

    @Test("A fix by hand turned back at once teaches nothing")
    func forgetsUndoneFix() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("db ", on: us)
        _ = typist.doubleShift()
        let undo = typist.doubleShift()
        #expect(undo.replacement?.text == "db ")
        #expect(undo.forgottenWord == "db")
        #expect(typist.engine.learnedWords.isEmpty)
    }

    @Test("Turning back a learned conversion makes the word an exception")
    func learnedThenTurnedBack() {
        var typist = Typist(Fixture.typingInUS)
        typist.engine.learnedWords = ["db"]
        #expect(typist.type("db ", on: us).last?.replacement?.text == "ви ")
        let undo = typist.doubleShift()
        #expect(undo.learnedException == "db")
        #expect(undo.forgottenWord == "db")
        #expect(typist.engine.learnedWords.isEmpty)
        #expect(typist.engine.exceptions == ["db"])
    }

    @Test("A fix in the middle of a word is learned whole when the word ends")
    func learnsWholeWordAfterMidWordFix() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("ghbd", on: us)
        _ = typist.doubleShift()
        typist.type("іт", on: ua)
        let output = typist.press(KeyCode.space)
        #expect(output.replacement == nil)
        #expect(output.learnedWord == "ghbdsn")
    }

    @Test("Single letters are not learned")
    func skipsSingleLetters() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("z ", on: us)
        let fix = typist.doubleShift()
        #expect(fix.replacement?.text == "я ")
        #expect(fix.learnedWord == nil)
    }

    @Test("Without layouts the engine passes everything")
    func passesWithoutLayouts() {
        var engine = LadEngine()
        #expect(engine.handle(.keyDown(keyCode: 5, modifiers: [], isRepeat: false)) == .pass)
        engine.setLayouts(Fixture.typingInUS)
        #expect(engine.layouts == Fixture.typingInUS)
    }
}
