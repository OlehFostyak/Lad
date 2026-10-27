import Foundation

/// Follows the typing one word at a time and decides when to retype a word in the other layout.
///
/// It keeps only the current word, the last few words and the last conversion, as key strokes in
/// memory; nothing is stored or logged. Anything that moves the caret or the focus forgets them.
public struct LadEngine: Sendable {
    /// The longest run of word keys Lad follows; longer runs are not words and are dropped.
    public static let maxWordLength = 40
    /// Boundary keys kept after a word (", " or ". ") for a double-Shift fix.
    static let maxTrailing = 3
    /// Finished words kept: undecided ones convert along with a following converted word.
    static let maxHistory = 3
    /// Shorter words are not learned from a double-Shift fix (single letters convert along anyway).
    static let minLearnedLength = 2

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
    private var overflowed = false
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
        overflowed = false
        shiftTaps.interrupt()
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
        /// By hand: the word this fix taught Lad; turning it back at once forgets it again.
        let taught: String?
    }

    private mutating func handleKey(_ keyCode: UInt16, modifiers: Modifiers, isRepeat: Bool) -> EngineOutput {
        shiftTaps.interrupt()
        guard let layouts else { return .pass }
        guard modifiers.isDisjoint(with: .shortcut), !isRepeat else {
            reset()
            return .pass
        }
        if keyCode == KeyCode.delete {
            deleteBackward(layouts: layouts)
            return .pass
        }
        if keyCode == KeyCode.returnKey || keyCode == KeyCode.keypadEnter {
            return finishLine(with: KeyStroke(keyCode: keyCode, shift: modifiers.contains(.shift)), layouts: layouts)
        }
        let stroke = KeyStroke(keyCode: keyCode, shift: modifiers.contains(.shift), capsLock: modifiers.contains(.capsLock))
        guard KeyCode.typesText(keyCode), let typed = layouts.current.text(for: stroke),
              let other = layouts.other.text(for: stroke) else {
            reset()
            return .pass
        }
        lastConversion = nil
        if Self.isWordKey(typed, in: layouts.current) || Self.isWordKey(other, in: layouts.other) {
            append(stroke)
            return .pass
        }
        return endWord(with: stroke, layouts: layouts)
    }

    /// A key types part of a word when it types a letter or an apostrophe in either layout: "[" in
    /// U.S. is "х" in Ukrainian, so it belongs to the word.
    private static func isWordKey(_ text: String, in table: LayoutTable) -> Bool {
        guard text.count == 1, let character = text.first, let language = table.language else { return false }
        return WordText.isWordCharacter(character, in: language)
    }

    private mutating func append(_ stroke: KeyStroke) {
        guard !overflowed else { return }
        guard word.count < Self.maxWordLength else {
            overflowed = true
            word = []
            history = []
            lessonFromLayoutID = nil
            return
        }
        word.append(stroke)
    }

    private mutating func endWord(with boundary: KeyStroke, layouts: LayoutPair) -> EngineOutput {
        if overflowed {
            overflowed = false
            history = []
            return .pass
        }
        guard !word.isEmpty else {
            extendTrailing(with: boundary)
            return .pass
        }
        let strokes = word
        word = []
        let lesson = takeLesson(for: strokes, layouts: layouts)
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
        guard fixesTwoCapitals, let detector, let language = layouts.current.language,
              let typed = layouts.current.text(for: strokes), !exceptions.contains(WordText.normalized(typed)),
              let fixed = CaseFix.twoInitialCapitals(typed, in: language), detector.isListed(fixed, in: language) else {
            return nil
        }
        let boundaryText = boundary.flatMap { layouts.current.text(for: $0) } ?? ""
        lastConversion = Conversion(
            original: typed + boundaryText, insertedCount: fixed.count + boundaryText.count,
            fromLayoutID: layouts.current.id, exception: WordText.normalized(typed), taught: nil
        )
        history = [TypedWord(strokes: strokes, trailing: boundary.map { [$0] } ?? [], verdict: nil, layoutID: layouts.current.id)]
        let replacement = Replacement(deleteCount: typed.count, text: fixed + boundaryText, layoutID: layouts.current.id)
        return EngineOutput(suppressesEvent: true, replacement: replacement)
    }

    /// Return or Enter ends the line. A word that converts is retyped and the key pressed again
    /// after it (the app may send the message right away), so nothing of the line is kept for an undo.
    private mutating func finishLine(with key: KeyStroke, layouts: LayoutPair) -> EngineOutput {
        defer { reset() }
        guard !overflowed, !word.isEmpty else { return .pass }
        let lesson = takeLesson(for: word, layouts: layouts)
        let segment = pendingStrokes(layouts: layouts) + word
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

    private func verdict(for strokes: [KeyStroke], layouts: LayoutPair) -> Verdict {
        guard isAutomatic, let typedLanguage = layouts.current.language, let otherLanguage = layouts.other.language,
              let typed = layouts.current.text(for: strokes), let other = layouts.other.text(for: strokes) else { return .keep }
        let normalized = WordText.normalized(typed)
        // On a Mac, Shift with Caps Lock still types capitals: a Caps Lock word is all caps whatever
        // was meant, so its case is no evidence (GHBDSN typed that way is ПРИВІТ).
        let capsLocked = strokes.allSatisfy(\.capsLock)
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
        guard !overflowed else {
            reset()
            return
        }
        if !word.isEmpty {
            word.removeLast()
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
        guard let fromLayoutID = lessonFromLayoutID else { return nil }
        lessonFromLayoutID = nil
        guard fromLayoutID == layouts.other.id, let typed = layouts.other.text(for: strokes) else { return nil }
        return learn(typed)
    }

    /// Adds a typed word to the learned words (it stops being an exception); nil when too short.
    private mutating func learn(_ typed: String) -> String? {
        let normalized = WordText.normalized(typed)
        guard normalized.count >= Self.minLearnedLength else { return nil }
        learnedWords.insert(normalized)
        exceptions.remove(normalized)
        return normalized
    }
}

// MARK: - Conversions

extension LadEngine {
    /// The boundary key has not reached the app: it is suppressed and retyped in the other layout
    /// after the word, together with the undecided words right before it that convert along.
    private mutating func convertAutomatically(_ strokes: [KeyStroke], boundary: KeyStroke, layouts: LayoutPair) -> EngineOutput {
        let segment = pendingStrokes(layouts: layouts) + strokes + [boundary]
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
    private func pendingStrokes(layouts: LayoutPair) -> [KeyStroke] {
        guard let detector, let typedLanguage = layouts.current.language, let otherLanguage = layouts.other.language else {
            return []
        }
        var strokes: [KeyStroke] = []
        for pending in history.reversed() {
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
            // A word Lad left alone, fixed by hand: Lad converts it on its own from now on.
            let typed = last.verdict == nil ? nil : layouts.current.text(for: last.strokes)
            let taught = typed.flatMap { learn($0) }
            var output = convertByHand(last.allStrokes, layouts: layouts, taught: taught)
            output.learnedWord = taught
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
            last.verdict = .keep
            history = [last]
        }
        let replacement = Replacement(deleteCount: conversion.insertedCount, text: conversion.original, layoutID: conversion.fromLayoutID)
        var output = EngineOutput(replacement: replacement)
        if let exception = conversion.exception {
            // An automatic conversion turned back: never again, even if it was learned.
            exceptions.insert(exception)
            output.learnedException = exception
            if learnedWords.remove(exception) != nil {
                output.forgottenWord = exception
            }
        }
        if let taught = conversion.taught {
            // A fix by hand turned back at once: it was no lesson.
            learnedWords.remove(taught)
            output.forgottenWord = taught
        }
        return output
    }
}
