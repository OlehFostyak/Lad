import Foundation

/// Follows the typing one word at a time and decides when to retype a word in the other layout.
///
/// It keeps only the current word, the last few words and the last conversion, as key strokes in
/// memory, and logs nothing. The only typed words it hands out for storing are the user's own
/// lists: exceptions (fixes turned back) and learned words (fixes made by hand that stood).
/// Anything that moves the caret or the focus forgets the rest.
public struct LadEngine: Sendable {
    /// The longest run of word keys Lad follows; longer runs are not words and are dropped.
    public static let maxWordLength = 40
    /// Boundary keys kept after a word (", " or ". ") for a double-Shift fix.
    static let maxTrailing = 3
    /// Finished words kept: undecided ones convert along with a following converted word.
    static let maxHistory = 3
    /// Shorter words are not learned from a double-Shift fix (single letters convert along anyway).
    static let minLearnedLength = 2
    /// Caps Lock words this short still read as acronyms (CSV, ДФС) and keep the all-caps rule.
    static let maxCapsLockAcronymLength = 3
    /// Punctuation that may end a line right after a word that converts at Return, in the layout
    /// the word converts into.
    static let closingPunctuation: Set<Character> = [".", ",", "!", "?", ";", ":", ")", "…"]
    /// Replies too short to convert anywhere else, but sent as a line of their own («ок⏎», «ok!⏎»)
    /// they are what they look like. Code tokens (jq, lt) are never one.
    static let shortReplies: [Language: Set<String>] = [
        .ukrainian: ["ок", "ну", "хм", "ха", "ах", "ох", "ух", "ех", "мм", "ага", "угу"],
        .english: ["ok", "hi", "no", "yo", "ya", "ha", "oh", "ah", "hm", "mm", "um"],
    ]
    /// Words with fewer letters never get a missing apostrophe added.
    static let minApostropheLength = 3
    /// Ukrainian letters an apostrophe may stand before (м'яч, п'ю, сім'є, з'їсти).
    static let iotatedVowels: Set<Character> = ["я", "ю", "є", "ї"]
    static let ukrainianVowels: Set<Character> = ["а", "е", "є", "и", "і", "ї", "о", "у", "ю", "я"]

    public private(set) var layouts: LayoutPair?
    public var detector: Detector?
    /// Off: words are never converted on their own, double Shift still fixes them.
    public var isAutomatic = true
    /// Return and keypad Enter convert the word before them too (the key is pressed again after).
    public var convertsOnReturn = true
    /// "ПРивіт" becomes "Привіт" at the space (when the fixed word is listed).
    public var fixesTwoCapitals = true
    /// Off: double Shift still fixes words but teaches nothing (in terminals, where the word may be
    /// a password typed at a prompt).
    public var learnsWords = true
    /// Live switching: a word converts while it is typed, as soon as its beginning can only be the
    /// other language's, not at its end.
    public var convertsWhileTyping = false
    /// Normalized typed words never to convert (the user turned them back).
    public var exceptions: Set<String> = []
    /// Normalized typed words always to convert (the user fixed them by hand).
    public var learnedWords: Set<String> = []

    private var word: [KeyStroke] = []
    /// Finished words, oldest first; the last one ends right before the caret (or the current word).
    private var history: [TypedWord] = []
    private var lastConversion: Conversion?
    /// The current word was fixed by hand mid-word, from this layout: it is learned whole at its end.
    private var lessonFromLayoutID: String?
    /// The keys up to the next boundary are not followed: a run too long to be a word, or a word
    /// another program typed into.
    private var skipsWord = false
    /// The current word converted while typed (live switching).
    private var live: LiveConversion?
    /// A live switch of the current word was turned back: the word stays as typed.
    private var holdsWord = false
    private var shiftTaps = ShiftTapDetector()

    public init(layouts: LayoutPair? = nil, detector: Detector? = nil) {
        self.layouts = layouts
        self.detector = detector
    }

    /// Replaces the layout pair (the enabled input sources changed) and forgets the typing.
    public mutating func setLayouts(_ layouts: LayoutPair?) {
        self.layouts = layouts
        reset()
    }

    /// The system now uses `layoutID`. Lad's own switches are already reflected; a switch by hand
    /// forgets the typing.
    public mutating func currentLayoutDidChange(to layoutID: String) {
        guard let layouts, layouts.current.id != layoutID else { return }
        if layouts.other.id == layoutID {
            self.layouts = layouts.swapped
        }
        reset()
    }

    public mutating func handle(_ event: InputEvent) -> EngineOutput {
        switch event {
        case let .keyDown(keyCode, modifiers, isRepeat):
            return handleKey(keyCode, modifiers: modifiers, isRepeat: isRepeat)
        case let .modifiersChanged(modifiers, time):
            return shiftTaps.register(modifiers, at: time) ? doubleShift() : .pass
        case .reset:
            reset()
            return .pass
        }
    }

    public mutating func reset() {
        word = []
        history = []
        lastConversion = nil
        lessonFromLayoutID = nil
        skipsWord = false
        live = nil
        holdsWord = false
        shiftTaps.interrupt()
    }

    /// Another program typed into the text (an auto-typed password, a text expander): Lad forgets
    /// the typing and follows nothing until the next word, since the user may finish this one.
    public mutating func skipWord() {
        reset()
        skipsWord = true
    }
}

// MARK: - Typing

extension LadEngine {
    /// A finished word, with the boundary keys typed after it.
    private struct TypedWord: Sendable, Equatable {
        var strokes: [KeyStroke]
        var trailing: [KeyStroke]
        /// Nil once the word was converted.
        var verdict: Verdict?
        /// The layout whose characters for the strokes are on screen.
        var layoutID: String

        var allStrokes: [KeyStroke] { strokes + trailing }
    }

    /// A word converted while it was typed, with the undecided words before it that converted along.
    private struct LiveConversion: Sendable, Equatable {
        let pending: [KeyStroke]
        let fromLayoutID: String
    }

    /// The last conversion, which a double Shift right after it turns back.
    private struct Conversion: Sendable, Equatable {
        /// The text as it was typed.
        let original: String
        let insertedCount: Int
        let fromLayoutID: String
        /// Automatic: the typed word, normalized; turning it back makes it an exception.
        let exception: String?
        /// By hand: the word this fix would teach Lad, learned only once the user types on.
        let taught: String?
        /// The keys as typed, when the fix changed them (a case fix, an added apostrophe): an undo
        /// puts them back.
        var typedStrokes: [KeyStroke]?
    }

    private mutating func handleKey(_ keyCode: UInt16, modifiers: Modifiers, isRepeat: Bool) -> EngineOutput {
        shiftTaps.interrupt()
        guard let layouts else { return .pass }
        let endsLine = keyCode == KeyCode.returnKey || keyCode == KeyCode.keypadEnter
        // Fn+Return on a laptop is Enter, not a shortcut.
        guard modifiers.subtracting(endsLine ? .function : []).isDisjoint(with: .shortcut), !isRepeat else {
            reset()
            return .pass
        }
        if keyCode == KeyCode.delete {
            deleteBackward(layouts: layouts)
            return .pass
        }
        // Typing on (or sending the line) after a fix by hand confirms the fix: it is learned now.
        if endsLine {
            let lesson = confirmLesson()
            var output = finishLine(with: KeyStroke(keyCode: keyCode, shift: modifiers.contains(.shift)), layouts: layouts)
            output.learnedWord = output.learnedWord ?? lesson
            return output
        }
        let stroke = KeyStroke(keyCode: keyCode, shift: modifiers.contains(.shift), capsLock: modifiers.contains(.capsLock))
        guard KeyCode.typesText(keyCode), let typed = layouts.current.text(for: stroke),
              let other = layouts.other.text(for: stroke) else {
            reset()
            return .pass
        }
        let lesson = confirmLesson()
        var output = EngineOutput.pass
        if Self.isWordKey(typed, in: layouts.current) || Self.isWordKey(other, in: layouts.other) {
            append(stroke)
            output = convertEarly(layouts: layouts) ?? .pass
        } else {
            output = endWord(with: stroke, layouts: layouts)
        }
        output.learnedWord = output.learnedWord ?? lesson
        return output
    }

    /// A key types part of a word when it types a letter or an apostrophe in either layout: "[" in
    /// U.S. is "х" in Ukrainian, so it belongs to the word.
    private static func isWordKey(_ text: String, in table: LayoutTable) -> Bool {
        guard text.count == 1, let character = text.first, let language = table.language else { return false }
        return WordText.isWordCharacter(character, in: language)
    }

    private mutating func append(_ stroke: KeyStroke) {
        guard !skipsWord else { return }
        guard word.count < Self.maxWordLength else {
            skipsWord = true
            word = []
            history = []
            lessonFromLayoutID = nil
            live = nil
            holdsWord = false
            return
        }
        word.append(stroke)
    }

    private mutating func endWord(with boundary: KeyStroke, layouts: LayoutPair) -> EngineOutput {
        if skipsWord {
            skipsWord = false
            history = []
            return .pass
        }
        guard !word.isEmpty else {
            lessonFromLayoutID = nil
            extendTrailing(with: boundary)
            return .pass
        }
        let strokes = word
        word = []
        if let live {
            // Converted while typed: the word stays as it is, and a double Shift right after turns
            // the whole conversion back, as after one at the space.
            self.live = nil
            let all = live.pending + strokes + [boundary]
            if let original = layouts.other.text(for: all), let shown = layouts.current.text(for: all) {
                lastConversion = Conversion(
                    original: original, insertedCount: shown.count, fromLayoutID: live.fromLayoutID,
                    exception: layouts.other.text(for: strokes).map(WordText.normalized), taught: nil
                )
            }
            history = [TypedWord(strokes: strokes, trailing: [boundary], verdict: nil, layoutID: layouts.current.id)]
            return .pass
        }
        if holdsWord {
            let output = keepHeldWord(strokes, layouts: layouts)
            remember(TypedWord(strokes: strokes, trailing: [boundary], verdict: .keep, layoutID: layouts.current.id))
            return output
        }
        // A word fixed mid-way is learned whole only when it ends at a space, not at a digit or symbol.
        let lesson = layouts.current.text(for: boundary) == " " ? takeLesson(for: strokes, layouts: layouts) : nil
        lessonFromLayoutID = nil
        let conversion = conversion(for: strokes, layouts: layouts)
        var verdict = conversion.verdict
        // Only a space converts right away: punctuation after a word is too often code or a path
        // (src/, jwt-), so the word waits and converts along with the next one.
        if verdict == .convert, layouts.current.text(for: boundary) != " " {
            verdict = .undecided
        }
        var output = EngineOutput.pass
        if verdict == .convert {
            output = convertAutomatically(strokes, into: conversion.converted, boundary: boundary, layouts: layouts)
        } else if layouts.current.text(for: boundary) == " ", let fix = fixCase(strokes, boundary: boundary, layouts: layouts) {
            output = fix
        } else {
            remember(TypedWord(strokes: strokes, trailing: [boundary], verdict: verdict, layoutID: layouts.current.id))
        }
        output.learnedWord = lesson
        return output
    }

    /// "ПРивіт" → "Привіт" in the same layout, when the fixed word is listed. The boundary key (if
    /// any) is suppressed and retyped after the word, like a conversion, so double Shift undoes it.
    private mutating func fixCase(_ strokes: [KeyStroke], boundary: KeyStroke?, layouts: LayoutPair) -> EngineOutput? {
        guard isAutomatic, fixesTwoCapitals, let detector, let language = layouts.current.language,
              let typed = layouts.current.text(for: strokes), !exceptions.contains(WordText.normalized(typed)),
              let fixed = CaseFix.twoInitialCapitals(typed, in: language), detector.isListed(fixed, in: language) else {
            return nil
        }
        let boundaryText = boundary.flatMap { layouts.current.text(for: $0) } ?? ""
        lastConversion = Conversion(
            original: typed + boundaryText, insertedCount: fixed.count + boundaryText.count,
            fromLayoutID: layouts.current.id, exception: WordText.normalized(typed), taught: nil, typedStrokes: strokes
        )
        // The word is followed on as it now reads (a later double Shift retypes "Привіт", not
        // "ПРивіт"); if its keys cannot type that, it is not followed at all.
        history = Self.strokes(strokes, recasedTo: fixed, in: layouts.current).map { fixedStrokes in
            [TypedWord(strokes: fixedStrokes, trailing: boundary.map { [$0] } ?? [], verdict: nil, layoutID: layouts.current.id)]
        } ?? []
        let replacement = Replacement(deleteCount: typed.count, text: fixed + boundaryText, layoutID: layouts.current.id)
        return EngineOutput(suppressesEvent: true, replacement: replacement)
    }

    /// The same keys with Shift flipped where a letter's case changed, if they type `text`.
    private static func strokes(_ strokes: [KeyStroke], recasedTo text: String, in table: LayoutTable) -> [KeyStroke]? {
        let characters = Array(text)
        guard characters.count == strokes.count else { return nil }
        let recased = zip(strokes, characters).map { stroke, character in
            table.text(for: stroke) == String(character)
                ? stroke : KeyStroke(keyCode: stroke.keyCode, shift: !stroke.shift, capsLock: stroke.capsLock)
        }
        return table.text(for: recased) == text ? recased : nil
    }

    /// Return or Enter ends the line. A word that converts is retyped and the key pressed again
    /// after it (the app may send the message right away), so nothing of the line is kept for an undo.
    private mutating func finishLine(with key: KeyStroke, layouts: LayoutPair) -> EngineOutput {
        defer { reset() }
        guard !skipsWord, live == nil else { return .pass }
        if holdsWord {
            return keepHeldWord(word, layouts: layouts)
        }
        guard !word.isEmpty else {
            return convertsOnReturn ? convertLastWord(endingLineWith: key, layouts: layouts) : .pass
        }
        let lesson = takeLesson(for: word, layouts: layouts)
        let pending = pendingStrokes(in: history[...], layouts: layouts)
        var (verdict, converted) = conversion(for: word, layouts: layouts)
        if verdict == .undecided, history.isEmpty, isShortReply(word, layouts: layouts) {
            (verdict, converted) = (.convert, word)
        }
        guard convertsOnReturn, verdict == .convert, let original = layouts.current.text(for: pending + word),
              let inserted = layouts.other.text(for: pending + converted) else {
            if convertsOnReturn, let fix = fixCase(word, boundary: nil, layouts: layouts)?.replacement {
                let replacement = Replacement(deleteCount: fix.deleteCount, text: fix.text, layoutID: fix.layoutID, followUpKey: key)
                return EngineOutput(suppressesEvent: true, replacement: replacement, learnedWord: lesson)
            }
            return EngineOutput(learnedWord: lesson)
        }
        self.layouts = layouts.swapped
        let replacement = Replacement(deleteCount: original.count, text: inserted, layoutID: layouts.other.id, followUpKey: key)
        return EngineOutput(suppressesEvent: true, replacement: replacement, learnedWord: lesson)
    }

    /// "ghbdsn/⏎" is «привіт.⏎»: when the line ends in punctuation right after a word, the word
    /// converts at Return as it would have at a space, the punctuation with it.
    private mutating func convertLastWord(endingLineWith key: KeyStroke, layouts: LayoutPair) -> EngineOutput {
        guard let last = history.last, last.verdict == .undecided, last.layoutID == layouts.current.id,
              let punctuation = layouts.other.text(for: last.trailing),
              punctuation.allSatisfy(Self.closingPunctuation.contains) else { return .pass }
        var (verdict, converted) = conversion(for: last.strokes, layouts: layouts)
        if verdict == .undecided, history.count == 1, isShortReply(last.strokes, layouts: layouts) {
            (verdict, converted) = (.convert, last.strokes)
        }
        let pending = pendingStrokes(in: history.dropLast(), layouts: layouts)
        guard verdict == .convert, let original = layouts.current.text(for: pending + last.allStrokes),
              let inserted = layouts.other.text(for: pending + converted + last.trailing) else {
            return .pass
        }
        self.layouts = layouts.swapped
        let replacement = Replacement(deleteCount: original.count, text: inserted, layoutID: layouts.other.id, followUpKey: key)
        return EngineOutput(suppressesEvent: true, replacement: replacement)
    }

    /// The verdict on the typed keys, and the keys they convert into: the same ones, or with the
    /// apostrophe Ukrainian needs and the typist skipped (vzx is «мяч», no word; it converts as «м'яч»).
    private func conversion(for strokes: [KeyStroke], layouts: LayoutPair) -> (verdict: Verdict, converted: [KeyStroke]) {
        let verdict = verdict(for: strokes, layouts: layouts)
        // Two keys are too often code ("d." is «вю», which «в'ю» would let through).
        guard verdict != .convert, strokes.count >= Self.minApostropheLength, layouts.other.language == .ukrainian,
              let apostrophe = layouts.other.stroke(for: WordText.apostrophe) ?? layouts.other.stroke(for: "ʼ"),
              let other = layouts.other.text(for: strokes) else { return (verdict, strokes) }
        let letters = Array(other.lowercased())
        guard letters.count == strokes.count else { return (verdict, strokes) }
        for index in letters.indices.dropFirst() where Self.iotatedVowels.contains(letters[index]) {
            let before = letters[index - 1]
            guard Language.ukrainian.isLetter(before), !Self.ukrainianVowels.contains(before), before != "ь" else { continue }
            var converted = strokes
            converted.insert(apostrophe, at: index)
            if self.verdict(for: strokes, layouts: layouts, into: converted) == .convert {
                return (.convert, converted)
            }
        }
        return (verdict, strokes)
    }

    /// Whether the keys type one of the other language's short replies, and nothing Lad keeps.
    private func isShortReply(_ strokes: [KeyStroke], layouts: LayoutPair) -> Bool {
        guard isAutomatic, let typedLanguage = layouts.current.language, let otherLanguage = layouts.other.language,
              let typed = layouts.current.text(for: strokes), let other = layouts.other.text(for: strokes),
              let reply = WordText.core(of: other, in: otherLanguage), Self.shortReplies[otherLanguage]?.contains(reply) == true,
              Detector.hasPlainCase(typed, in: typedLanguage) else { return false }
        let normalized = WordText.normalized(typed)
        return !exceptions.contains(normalized) && !(typedLanguage == .english && Detector.codeTokens.contains(normalized))
    }

    /// `converted`: the keys the word would convert into, when they differ from the typed ones.
    private func verdict(for strokes: [KeyStroke], layouts: LayoutPair, into converted: [KeyStroke]? = nil) -> Verdict {
        guard isAutomatic, let typedLanguage = layouts.current.language, let otherLanguage = layouts.other.language,
              let typed = layouts.current.text(for: strokes),
              let other = layouts.other.text(for: converted ?? strokes) else { return .keep }
        let normalized = WordText.normalized(typed)
        // On a Mac, Shift with Caps Lock still types capitals: a Caps Lock word is all caps whatever
        // was meant, so its case is no evidence (GHBDSN typed that way is ПРИВІТ). Short ones still
        // read as acronyms (CSV is no «СІМ»).
        let capsLocked = strokes.count > Self.maxCapsLockAcronymLength && strokes.allSatisfy(\.capsLock)
        let hasPlainCase = capsLocked || Detector.hasPlainCase(typed, in: typedLanguage)
        if converted == nil, learnedWords.contains(normalized), !exceptions.contains(normalized), hasPlainCase {
            return .convert
        }
        guard let detector else { return .keep }
        return detector.verdict(
            typed: typed, in: typedLanguage, other: other, in: otherLanguage, exceptions: exceptions, capsLocked: capsLocked
        )
    }

    private mutating func remember(_ typedWord: TypedWord) {
        history.append(typedWord)
        if history.count > Self.maxHistory {
            history.removeFirst()
        }
    }

    private mutating func extendTrailing(with boundary: KeyStroke) {
        guard var last = history.popLast(), last.trailing.count < Self.maxTrailing else {
            history = []
            return
        }
        last.trailing.append(boundary)
        history.append(last)
    }

    private mutating func deleteBackward(layouts: LayoutPair) {
        lastConversion = nil
        guard !skipsWord else {
            reset()
            return
        }
        if !word.isEmpty {
            word.removeLast()
            if word.isEmpty {
                lessonFromLayoutID = nil
                live = nil
                holdsWord = false
            }
            return
        }
        // Deleting the boundary after the last word puts the caret back at the word's end.
        guard var last = history.popLast(), !last.trailing.isEmpty, last.layoutID == layouts.current.id else {
            reset()
            return
        }
        last.trailing.removeLast()
        if last.trailing.isEmpty {
            word = last.strokes
        } else {
            history.append(last)
        }
    }
}

// MARK: - Learning

extension LadEngine {
    /// After a double-Shift fix in the middle of the word: the whole word as typed in the wrong
    /// layout, learned now that it is complete.
    private mutating func takeLesson(for strokes: [KeyStroke], layouts: LayoutPair) -> String? {
        guard let fromLayoutID = lessonFromLayoutID, fromLayoutID == layouts.other.id,
              let typed = layouts.other.text(for: strokes), let converted = layouts.current.text(for: strokes),
              let word = lesson(typed: typed, in: layouts.other, converted: converted, in: layouts.current) else { return nil }
        learn(word)
        return word
    }

    /// The pending lesson of a fix by hand, learned now that the user typed on.
    private mutating func confirmLesson() -> String? {
        defer { lastConversion = nil }
        guard let word = lastConversion?.taught else { return nil }
        learn(word)
        return word
    }

    /// A fixed word worth learning: long enough, no code token, not a word of the layout it was
    /// typed in, and once converted a listed word, or one that spells like a word (реді, names)
    /// while the typed keys spell like none. So keyboard mash and random passwords fixed by hand
    /// are never learned (or stored).
    private func lesson(typed: String, in typedTable: LayoutTable, converted: String, in convertedTable: LayoutTable) -> String? {
        guard learnsWords, let detector, let typedLanguage = typedTable.language, let convertedLanguage = convertedTable.language else {
            return nil
        }
        let word = WordText.normalized(typed)
        guard word.count >= Self.minLearnedLength,
              !(typedLanguage == .english && Detector.codeTokens.contains(word)),
              !detector.isListed(typed, in: typedLanguage) else { return nil }
        let isWord = detector.isListed(converted, in: convertedLanguage)
            || (detector.isLearnable(converted, in: convertedLanguage) && !detector.looksLikeWord(typed, in: typedLanguage))
        return isWord ? word : nil
    }

    /// Adds a word to the learned words; it stops being an exception.
    private mutating func learn(_ word: String) {
        learnedWords.insert(word)
        exceptions.remove(word)
    }
}

// MARK: - Conversions

extension LadEngine {
    /// The boundary key has not reached the app: it is suppressed and retyped in the other layout
    /// after the word, together with the undecided words right before it that convert along.
    private mutating func convertAutomatically(
        _ strokes: [KeyStroke], into converted: [KeyStroke], boundary: KeyStroke, layouts: LayoutPair
    ) -> EngineOutput {
        let pending = pendingStrokes(in: history[...], layouts: layouts)
        guard let original = layouts.current.text(for: pending + strokes + [boundary]),
              let inserted = layouts.other.text(for: pending + converted + [boundary]),
              let typedBoundary = layouts.current.text(for: boundary) else { return .pass }
        self.layouts = layouts.swapped
        lastConversion = Conversion(
            original: original, insertedCount: inserted.count, fromLayoutID: layouts.current.id,
            exception: layouts.current.text(for: strokes).map(WordText.normalized), taught: nil,
            typedStrokes: converted == strokes ? nil : strokes
        )
        history = [TypedWord(strokes: converted, trailing: [boundary], verdict: nil, layoutID: layouts.other.id)]
        let replacement = Replacement(
            deleteCount: original.count - typedBoundary.count, text: inserted, layoutID: layouts.other.id
        )
        return EngineOutput(suppressesEvent: true, replacement: replacement)
    }

    /// Live switching: the word converts as soon as its beginning can only be the other language's.
    /// The key is suppressed and typed with the rest in the other layout, the undecided words right
    /// before it included, and the user types the rest of the word in the new layout.
    private mutating func convertEarly(layouts: LayoutPair) -> EngineOutput? {
        guard convertsWhileTyping, isAutomatic, live == nil, !holdsWord, !skipsWord, lessonFromLayoutID == nil,
              let detector, let typedLanguage = layouts.current.language, let otherLanguage = layouts.other.language,
              let typed = layouts.current.text(for: word), let other = layouts.other.text(for: word),
              detector.convertsEarly(typed: typed, in: typedLanguage, other: other, in: otherLanguage, exceptions: exceptions)
        else { return nil }
        let pending = pendingStrokes(in: history[...], layouts: layouts)
        guard let shown = layouts.current.text(for: pending + word.dropLast()),
              let inserted = layouts.other.text(for: pending + word) else { return nil }
        self.layouts = layouts.swapped
        live = LiveConversion(pending: pending, fromLayoutID: layouts.current.id)
        history = []
        lastConversion = nil
        return EngineOutput(suppressesEvent: true, replacement: Replacement(deleteCount: shown.count, text: inserted, layoutID: layouts.other.id))
    }

    /// Double Shift while a word converted early is still being typed: it goes back to the layout
    /// it was typed in, with the words that converted along, and stays so to its end.
    private mutating func undoEarly(_ live: LiveConversion, layouts: LayoutPair) -> EngineOutput {
        self.live = nil
        let all = live.pending + word
        guard let shown = layouts.current.text(for: all), let typed = layouts.other.text(for: all) else {
            reset()
            return .pass
        }
        self.layouts = layouts.swapped
        holdsWord = true
        history = []
        return EngineOutput(replacement: Replacement(deleteCount: shown.count, text: typed, layoutID: layouts.other.id), isUndo: true)
    }

    /// The end of a word whose live switch was turned back: it becomes an exception, so it neither
    /// converts early nor at its end again.
    private mutating func keepHeldWord(_ strokes: [KeyStroke], layouts: LayoutPair) -> EngineOutput {
        holdsWord = false
        guard let typed = layouts.current.text(for: strokes) else { return .pass }
        let exception = WordText.normalized(typed)
        exceptions.insert(exception)
        var output = EngineOutput(learnedException: exception)
        if learnedWords.remove(exception) != nil {
            output.forgottenWord = exception
        }
        return output
    }

    /// The strokes of the undecided words right before the current one that convert along with it
    /// (nearest first, stopping at the first that does not). Each must be joined to the next by a
    /// space (after at most a couple of punctuation keys: "ghbdsn? zr" is "привіт, як") or a hyphen.
    private func pendingStrokes(in words: ArraySlice<TypedWord>, layouts: LayoutPair) -> [KeyStroke] {
        guard let detector, let typedLanguage = layouts.current.language, let otherLanguage = layouts.other.language else {
            return []
        }
        var strokes: [KeyStroke] = []
        for pending in words.reversed() {
            guard pending.verdict == .undecided, pending.layoutID == layouts.current.id,
                  let joint = layouts.current.text(for: pending.trailing),
                  joint == "-" || (joint.last == " " && !joint.dropLast().contains(" ")),
                  let typed = layouts.current.text(for: pending.strokes), let other = layouts.other.text(for: pending.strokes),
                  !exceptions.contains(WordText.normalized(typed)),
                  detector.convertsAlong(typed: typed, in: typedLanguage, other: other, in: otherLanguage) else { break }
            strokes = pending.allStrokes + strokes
        }
        return strokes
    }

    /// Double Shift: turn back the last conversion, else convert the word being typed, else the
    /// last word (and learn it), else ask for the selection.
    private mutating func doubleShift() -> EngineOutput {
        guard let layouts else { return .pass }
        if let live, !word.isEmpty {
            return undoEarly(live, layouts: layouts)
        }
        if let conversion = lastConversion {
            return undo(conversion, layouts: layouts)
        }
        if !word.isEmpty {
            let output = convertByHand(word, layouts: layouts, taught: nil)
            if output.replacement != nil {
                lessonFromLayoutID = layouts.current.id
            }
            return output
        }
        if let last = history.last, last.layoutID == layouts.current.id {
            // A word Lad left alone, fixed by hand: once the user types on, Lad converts it itself.
            var taught: String?
            if last.verdict != nil, let typed = layouts.current.text(for: last.strokes),
               let converted = layouts.other.text(for: last.strokes) {
                taught = lesson(typed: typed, in: layouts.current, converted: converted, in: layouts.other)
            }
            let output = convertByHand(last.allStrokes, layouts: layouts, taught: taught)
            history = [TypedWord(strokes: last.strokes, trailing: last.trailing, verdict: nil, layoutID: layouts.other.id)]
            return output
        }
        return EngineOutput(convertsSelection: true)
    }

    private mutating func convertByHand(_ strokes: [KeyStroke], layouts: LayoutPair, taught: String?) -> EngineOutput {
        guard let typed = layouts.current.text(for: strokes), let other = layouts.other.text(for: strokes) else {
            return .pass
        }
        self.layouts = layouts.swapped
        lastConversion = Conversion(
            original: typed, insertedCount: other.count, fromLayoutID: layouts.current.id, exception: nil, taught: taught
        )
        return EngineOutput(replacement: Replacement(deleteCount: typed.count, text: other, layoutID: layouts.other.id))
    }

    private mutating func undo(_ conversion: Conversion, layouts: LayoutPair) -> EngineOutput {
        lastConversion = nil
        lessonFromLayoutID = nil
        // A case fix stayed in the same layout; a conversion switches back.
        let switchesBack = conversion.fromLayoutID == layouts.other.id
        guard switchesBack || conversion.fromLayoutID == layouts.current.id else {
            reset()
            return .pass
        }
        if switchesBack {
            self.layouts = layouts.swapped
        }
        if var last = history.popLast() {
            if switchesBack, last.layoutID == layouts.current.id {
                last.layoutID = layouts.other.id
            }
            if let typedStrokes = conversion.typedStrokes {
                last.strokes = typedStrokes
            }
            last.verdict = .keep
            history = [last]
        }
        let replacement = Replacement(deleteCount: conversion.insertedCount, text: conversion.original, layoutID: conversion.fromLayoutID)
        var output = EngineOutput(replacement: replacement, isUndo: true)
        if let exception = conversion.exception {
            // An automatic conversion turned back: never again, even if it was learned.
            exceptions.insert(exception)
            output.learnedException = exception
            if learnedWords.remove(exception) != nil {
                output.forgottenWord = exception
            }
        }
        // A fix by hand turned back at once was no lesson; it was never learned.
        return output
    }
}
