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

    public private(set) var layouts: LayoutPair?
    public var detector: Detector?
    /// Off: words are never converted on their own, double Shift still fixes them.
    public var isAutomatic = true
    /// Return and keypad Enter convert the word before them too (the key is pressed again after).
    public var convertsOnReturn = true
    /// "ПРивіт" becomes "Привіт" at the space (when the fixed word is listed).
    public var fixesTwoCapitals = true
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
        /// A case fix: the keys as typed, which an undo puts back.
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
        // A word fixed mid-way is learned whole only when it ends at a space, not at a digit or symbol.
        let lesson = layouts.current.text(for: boundary) == " " ? takeLesson(for: strokes, layouts: layouts) : nil
        lessonFromLayoutID = nil
        var verdict = verdict(for: strokes, layouts: layouts)
        // Only a space converts right away: punctuation after a word is too often code or a path
        // (src/, jwt-), so the word waits and converts along with the next one.
        if verdict == .convert, layouts.current.text(for: boundary) != " " {
            verdict = .undecided
        }
        var output = EngineOutput.pass
        if verdict == .convert {
            output = convertAutomatically(strokes, boundary: boundary, layouts: layouts)
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
        guard !skipsWord else { return .pass }
        guard !word.isEmpty else {
            return convertsOnReturn ? convertLastWord(endingLineWith: key, layouts: layouts) : .pass
        }
        let lesson = takeLesson(for: word, layouts: layouts)
        let segment = pendingStrokes(in: history[...], layouts: layouts) + word
        guard convertsOnReturn, verdict(for: word, layouts: layouts) == .convert,
              let original = layouts.current.text(for: segment), let inserted = layouts.other.text(for: segment) else {
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
              punctuation.allSatisfy(Self.closingPunctuation.contains),
              verdict(for: last.strokes, layouts: layouts) == .convert else { return .pass }
        let segment = pendingStrokes(in: history.dropLast(), layouts: layouts) + last.allStrokes
        guard let original = layouts.current.text(for: segment), let inserted = layouts.other.text(for: segment) else {
            return .pass
        }
        self.layouts = layouts.swapped
        let replacement = Replacement(deleteCount: original.count, text: inserted, layoutID: layouts.other.id, followUpKey: key)
        return EngineOutput(suppressesEvent: true, replacement: replacement)
    }

    private func verdict(for strokes: [KeyStroke], layouts: LayoutPair) -> Verdict {
        guard isAutomatic, let typedLanguage = layouts.current.language, let otherLanguage = layouts.other.language,
              let typed = layouts.current.text(for: strokes), let other = layouts.other.text(for: strokes) else { return .keep }
        let normalized = WordText.normalized(typed)
        // On a Mac, Shift with Caps Lock still types capitals: a Caps Lock word is all caps whatever
        // was meant, so its case is no evidence (GHBDSN typed that way is ПРИВІТ). Short ones still
        // read as acronyms (CSV is no «СІМ»).
        let capsLocked = strokes.count > Self.maxCapsLockAcronymLength && strokes.allSatisfy(\.capsLock)
        let hasPlainCase = capsLocked || Detector.hasPlainCase(typed, in: typedLanguage)
        if learnedWords.contains(normalized), !exceptions.contains(normalized), hasPlainCase {
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
    /// typed in, and a listed word once converted. So keyboard mash, and a password fixed by hand,
    /// are never learned (or stored).
    private func lesson(typed: String, in typedTable: LayoutTable, converted: String, in convertedTable: LayoutTable) -> String? {
        guard let detector, let typedLanguage = typedTable.language, let convertedLanguage = convertedTable.language else {
            return nil
        }
        let word = WordText.normalized(typed)
        guard word.count >= Self.minLearnedLength,
              !(typedLanguage == .english && Detector.codeTokens.contains(word)),
              !detector.isListed(typed, in: typedLanguage),
              detector.isListed(converted, in: convertedLanguage) else { return nil }
        return word
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
    private mutating func convertAutomatically(_ strokes: [KeyStroke], boundary: KeyStroke, layouts: LayoutPair) -> EngineOutput {
        let segment = pendingStrokes(in: history[...], layouts: layouts) + strokes + [boundary]
        guard let original = layouts.current.text(for: segment), let inserted = layouts.other.text(for: segment),
              let typedBoundary = layouts.current.text(for: boundary) else { return .pass }
        self.layouts = layouts.swapped
        lastConversion = Conversion(
            original: original, insertedCount: inserted.count, fromLayoutID: layouts.current.id,
            exception: layouts.current.text(for: strokes).map(WordText.normalized), taught: nil
        )
        history = [TypedWord(strokes: strokes, trailing: [boundary], verdict: nil, layoutID: layouts.other.id)]
        let replacement = Replacement(
            deleteCount: original.count - typedBoundary.count, text: inserted, layoutID: layouts.other.id
        )
        return EngineOutput(suppressesEvent: true, replacement: replacement)
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
