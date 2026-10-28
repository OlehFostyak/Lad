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

    @Test("A line that ends in punctuation right after a word converts at Return, punctuation too")
    func convertsBeforeClosingPunctuation() {
        var period = Typist(Fixture.typingInUS)
        period.type("ghbdsn/", on: us)
        #expect(period.pressReturn().replacement == Replacement(
            deleteCount: 7, text: "привіт.", layoutID: ua.id, followUpKey: KeyStroke(keyCode: KeyCode.returnKey)
        ))
        var chain = Typist(Fixture.typingInUS)
        chain.type("z [jxe/", on: us)
        #expect(chain.pressReturn().replacement?.text == "я хочу.")
        var question = Typist(Fixture.typingInUS)
        question.type("cghfdb&", on: us)
        #expect(question.pressReturn().replacement?.text == "справи?")
        var path = Typist(Fixture.typingInUS)
        path.type("cd src/", on: us)
        #expect(path.pressReturn() == .pass)
        var hyphen = Typist(Fixture.typingInUS)
        hyphen.type("ghbdsn-", on: us)
        #expect(hyphen.pressReturn() == .pass)
    }

    @Test("Fn+Return on a laptop is Enter, not a shortcut")
    func convertsAtFnReturn() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("ghbdsn", on: us)
        #expect(typist.press(KeyCode.keypadEnter, .function).replacement?.text == "привіт")
    }

    @Test("Pending words convert along at Return")
    func convertsPendingAtReturn() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("z [jxe", on: us)
        #expect(typist.pressReturn().replacement == Replacement(
            deleteCount: 6, text: "я хочу", layoutID: ua.id, followUpKey: KeyStroke(keyCode: KeyCode.returnKey)
        ))
    }

    @Test("A word fixed by hand is learned once the user types on, then converts on its own")
    func learnsFromFixByHand() throws {
        var typist = Typist(Fixture.typingInUS, detector: Fixture.cautiousDetector)
        #expect(typist.type("ghbdsn ", on: us).isEmpty)
        let fix = typist.doubleShift()
        #expect(fix.replacement?.text == "привіт ")
        #expect(fix.learnedWord == nil)
        #expect(typist.type("я", on: ua).first?.learnedWord == "ghbdsn")
        #expect(typist.engine.learnedWords == ["ghbdsn"])
        typist.engine.currentLayoutDidChange(to: us.id)
        let output = try #require(typist.type("ghbdsn ", on: us).last)
        #expect(output.replacement == Replacement(deleteCount: 6, text: "привіт ", layoutID: ua.id))
    }

    @Test("A short word Lad leaves alone is learned from a fix by hand")
    func learnsShortWord() throws {
        var typist = Typist(Fixture.typingInUA)
        #expect(typist.type("рф ", on: ua).isEmpty)
        #expect(typist.doubleShift().replacement?.text == "ha ")
        #expect(typist.type("x", on: us).first?.learnedWord == "рф")
        typist.engine.reset()
        typist.engine.currentLayoutDidChange(to: ua.id)
        let output = try #require(typist.type("рф ", on: ua).last)
        #expect(output.replacement == Replacement(deleteCount: 2, text: "ha ", layoutID: us.id))
    }

    @Test("A fix by hand turned back at once teaches nothing")
    func forgetsUndoneFix() {
        var typist = Typist(Fixture.typingInUS, detector: Fixture.cautiousDetector)
        typist.type("ghbdsn ", on: us)
        _ = typist.doubleShift()
        let undo = typist.doubleShift()
        #expect(undo.replacement?.text == "ghbdsn ")
        #expect(undo.forgottenWord == nil)
        #expect(typist.type("x", on: us).isEmpty)
        #expect(typist.engine.learnedWords.isEmpty)
    }

    @Test("Code tokens, keyboard mash and real words are not learned")
    func learnsOnlyWords() {
        for typed in ["db ", "qzxvkw ", "here "] {
            var typist = Typist(Fixture.typingInUS, detector: Fixture.cautiousDetector)
            typist.type(typed, on: us)
            _ = typist.doubleShift()
            #expect(typist.press(KeyCode.space).learnedWord == nil, "\(typed) was learned")
            #expect(typist.engine.learnedWords.isEmpty)
        }
    }

    @Test("Turning back a learned conversion makes the word an exception")
    func learnedThenTurnedBack() {
        var typist = Typist(Fixture.typingInUS, detector: Fixture.cautiousDetector)
        typist.engine.learnedWords = ["ghbdsn"]
        #expect(typist.type("ghbdsn ", on: us).last?.replacement?.text == "привіт ")
        let undo = typist.doubleShift()
        #expect(undo.learnedException == "ghbdsn")
        #expect(undo.forgottenWord == "ghbdsn")
        #expect(typist.engine.learnedWords.isEmpty)
        #expect(typist.engine.exceptions == ["ghbdsn"])
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

    @Test("A fix in the middle of a word that ends at a digit is not learned")
    func skipsWordsEndingAtSymbols() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("ghbd", on: us)
        _ = typist.doubleShift()
        typist.type("іт", on: ua)
        #expect(typist.press(18).learnedWord == nil)
    }

    @Test("A word fixed mid-way and then deleted teaches nothing")
    func dropsLessonOfDeletedWord() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("ghbd", on: us)
        _ = typist.doubleShift()
        for _ in 0..<4 {
            typist.press(KeyCode.delete)
        }
        typist.type("привіт", on: ua)
        #expect(typist.press(KeyCode.space).learnedWord == nil)
        #expect(typist.engine.learnedWords.isEmpty)
    }

    @Test("After another program typed, the rest of its word is not followed")
    func skipsProgramWord() throws {
        var typist = Typist(Fixture.typingInUS)
        typist.engine.skipWord()
        #expect(typist.type("bdsn ", on: us).isEmpty)
        let output = try #require(typist.type("ghbdsn ", on: us).last)
        #expect(output.replacement?.text == "привіт ")
    }

    @Test("Single letters are not learned")
    func skipsSingleLetters() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("z ", on: us)
        let fix = typist.doubleShift()
        #expect(fix.replacement?.text == "я ")
        #expect(typist.press(KeyCode.space).learnedWord == nil)
    }

    @Test("Without layouts the engine passes everything")
    func passesWithoutLayouts() {
        var engine = LadEngine()
        #expect(engine.handle(.keyDown(keyCode: 5, modifiers: [], isRepeat: false)) == .pass)
        engine.setLayouts(Fixture.typingInUS)
        #expect(engine.layouts == Fixture.typingInUS)
    }
}

@Suite("Apostrophes")
struct ApostropheTests {
    private let us = Fixture.us
    private let ua = Fixture.ua

    @Test("A word typed without its apostrophe converts with it, and an undo puts the keys back")
    func addsApostrophe() throws {
        var typist = Typist(Fixture.typingInUS)
        let output = try #require(typist.type("vzx ", on: us).last)
        #expect(output.replacement == Replacement(deleteCount: 3, text: "м'яч ", layoutID: ua.id))
        let undo = typist.doubleShift()
        #expect(undo.replacement == Replacement(deleteCount: 5, text: "vzx ", layoutID: us.id))
        #expect(undo.learnedException == "vzx")
    }

    @Test("The apostrophe goes after the consonant, in any case", arguments: [
        ("пять", "п'ять"), ("Мяч", "М'яч"), ("сімях", "сім'ях"), ("зїсти", "з'їсти"),
    ])
    func placesApostrophe(skipped: String, spelled: String) throws {
        var typist = Typist(Fixture.typingInUS)
        let output = try #require(typist.type(Fixture.retype(skipped, from: ua, to: us) + " ", on: us).last)
        #expect(output.replacement?.text == spelled + " ")
    }

    @Test("Words that need no apostrophe, or are no word with one, are left as they are")
    func leavesOthersAlone() throws {
        var typist = Typist(Fixture.typingInUS)
        let output = try #require(typist.type("ghbdsn ", on: us).last)
        #expect(output.replacement?.text == "привіт ")
        var mash = Typist(Fixture.typingInUS)
        #expect(mash.type("qzx ", on: us).isEmpty)
    }

    @Test("At Return too, with the line's punctuation")
    func addsApostropheAtReturn() throws {
        var typist = Typist(Fixture.typingInUS)
        typist.type("vzx", on: us)
        #expect(typist.pressReturn().replacement == Replacement(deleteCount: 3, text: "м'яч", layoutID: ua.id, followUpKey: KeyStroke(keyCode: KeyCode.returnKey)))
        var dotted = Typist(Fixture.typingInUS)
        dotted.type("vzx/", on: us)
        #expect(dotted.pressReturn().replacement?.text == "м'яч.")
    }
}

@Suite("Short replies")
struct ShortReplyTests {
    private let us = Fixture.us
    private let ua = Fixture.ua
    private let returnKey = KeyStroke(keyCode: KeyCode.returnKey)

    @Test("A short reply alone on its line converts at Return", arguments: ["ок", "ну", "Ок"])
    func convertsAloneAtReturn(reply: String) {
        var typist = Typist(Fixture.typingInUS)
        typist.type(Fixture.retype(reply, from: ua, to: us), on: us)
        #expect(typist.pressReturn().replacement == Replacement(deleteCount: 2, text: reply, layoutID: ua.id, followUpKey: returnKey))
    }

    @Test("With the line's punctuation, and in English too")
    func convertsWithPunctuation() {
        var typist = Typist(Fixture.typingInUS)
        typist.type("jr!", on: us)
        #expect(typist.pressReturn().replacement?.text == "ок!")
        var english = Typist(Fixture.typingInUA)
        english.type("щл", on: ua)
        #expect(english.pressReturn().replacement?.text == "ok")
    }

    @Test("Not after other words, not at a space, and never a code token")
    func staysOtherwise() {
        var sentence = Typist(Fixture.typingInUS)
        sentence.type("is jr", on: us)
        #expect(sentence.pressReturn().replacement == nil)
        var spaced = Typist(Fixture.typingInUS)
        #expect(spaced.type("jr ", on: us).isEmpty)
        var code = Typist(Fixture.typingInUS)
        code.type("jq", on: us)
        #expect(code.pressReturn().replacement == nil)
    }
}

@Suite("Learning words outside the dictionary")
struct UnlistedLearningTests {
    private let us = Fixture.us
    private let ua = Fixture.ua

    /// Types the word in the wrong layout, fixes it with double Shift, types on; returns what was learned.
    private func learn(_ word: String, typing typist: inout Typist) -> String? {
        let typed = Fixture.retype(word, from: ua, to: us)
        #expect(typist.type(typed + " ", on: us).isEmpty, "\(typed) converted by itself")
        #expect(typist.doubleShift().replacement?.text == word + " ")
        return typist.type("я", on: ua).first?.learnedWord
    }

    @Test("A word that spells like Ukrainian is learned, then converts by itself", arguments: ["реді", "кринж"])
    func learnsWordLikeWord(word: String) throws {
        var typist = Typist(Fixture.typingInUS)
        let typed = Fixture.retype(word, from: ua, to: us)
        #expect(learn(word, typing: &typist) == typed)
        typist.engine.reset()
        typist.engine.currentLayoutDidChange(to: us.id)
        let output = try #require(typist.type(typed + " ", on: us).last)
        #expect(output.replacement?.text == word + " ")
    }

    @Test("Keyboard mash is never learned")
    func skipsMash() {
        var typist = Typist(Fixture.typingInUS)
        #expect(learn("йячмцф", typing: &typist) == nil)
        #expect(typist.engine.learnedWords.isEmpty)
    }

    @Test("Nothing is learned where learning is off (terminals)")
    func skipsWhenOff() {
        var typist = Typist(Fixture.typingInUS)
        typist.engine.learnsWords = false
        #expect(learn("реді", typing: &typist) == nil)
        var listed = Typist(Fixture.typingInUS, detector: Fixture.cautiousDetector)
        listed.engine.learnsWords = false
        listed.type("ghbdsn ", on: us)
        #expect(listed.doubleShift().replacement?.text == "привіт ")
        #expect(listed.type("я", on: ua).first?.learnedWord == nil)
    }
}

@Suite("Live switching")
struct LiveSwitchingTests {
    private let us = Fixture.us
    private let ua = Fixture.ua

    private func typist(_ layouts: LayoutPair) -> Typist {
        var typist = Typist(layouts)
        typist.engine.convertsWhileTyping = true
        return typist
    }

    @Test("A Ukrainian word typed in U.S. converts before its end, and the rest is typed in Ukrainian")
    func convertsUkrainianEarly() throws {
        var typist = typist(Fixture.typingInUS)
        let outputs = typist.type("ghbdsn ", on: us)
        let output = try #require(outputs.first)
        #expect(outputs.count == 1)
        #expect(output.suppressesEvent)
        #expect(output.replacement == Replacement(deleteCount: 3, text: "прив", layoutID: ua.id))
        #expect(typist.engine.layouts?.current.id == ua.id)
    }

    @Test("An English word typed in Ukrainian converts before its end")
    func convertsEnglishEarly() throws {
        var typist = typist(Fixture.typingInUA)
        let output = try #require(typist.type("руддщ ", on: ua).first)
        #expect(output.replacement?.layoutID == us.id)
        #expect(output.replacement.map { $0.text.count - $0.deleteCount } == 1)
        #expect("hello".hasPrefix(output.replacement?.text ?? "-"))
    }

    @Test("Words typed in the right layout, and code, never switch early")
    func keepsRightWords() {
        var english = typist(Fixture.typingInUS)
        #expect(english.type("hello world, this is git kubectl get pods src csv ", on: us).isEmpty)
        var ukrainian = typist(Fixture.typingInUA)
        #expect(ukrainian.type("привіт, як справи ківі ", on: ua).isEmpty)
    }

    @Test("Off by default")
    func offByDefault() {
        var typist = Typist(Fixture.typingInUS)
        #expect(typist.type("ghbd", on: us).isEmpty)
    }

    @Test("Double Shift after the word turns the whole switch back and keeps the word an exception")
    func undoesAfterWord() throws {
        var typist = typist(Fixture.typingInUS)
        typist.type("ghbdsn ", on: us)
        let undo = typist.doubleShift()
        #expect(undo.replacement == Replacement(deleteCount: 7, text: "ghbdsn ", layoutID: us.id))
        #expect(undo.learnedException == "ghbdsn")
        #expect(typist.type("ghbdsn ", on: us).isEmpty)
    }

    @Test("Double Shift mid-word turns the switch back; the word stays and becomes an exception")
    func undoesMidWord() throws {
        var typist = typist(Fixture.typingInUS)
        typist.type("ghbd", on: us)
        let undo = typist.doubleShift()
        #expect(undo.replacement == Replacement(deleteCount: 4, text: "ghbd", layoutID: us.id))
        #expect(undo.isUndo)
        let end = typist.type("sn ", on: us)
        #expect(end.first?.learnedException == "ghbdsn")
        #expect(end.allSatisfy { $0.replacement == nil })
        #expect(typist.type("ghbdsn ", on: us).isEmpty)
    }

    @Test("Undecided words right before it switch along")
    func convertsPendingAlong() throws {
        var typist = typist(Fixture.typingInUS)
        let output = try #require(typist.type("z ghbdsn", on: us).first)
        #expect(output.replacement == Replacement(deleteCount: 5, text: "я прив", layoutID: ua.id))
    }
}
