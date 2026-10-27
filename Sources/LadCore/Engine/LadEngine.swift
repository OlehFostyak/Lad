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

    public private(set) var layouts: LayoutPair?
    public var detector: Detector?
    /// Off: words are never converted on their own, double Shift still fixes them.
    public var isAutomatic = true
    /// Return and keypad Enter convert the word before them too (the key is pressed again after).
    public var convertsOnReturn = true
    /// Normalized typed words never to convert (the user turned them back).
    public var exceptions: Set<String> = []

    private var word: [KeyStroke] = []
    /// Finished words, oldest first; the last one ends right before the caret (or the current word).
    private var history: [TypedWord] = []
    private var lastConversion: Conversion?
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
        /// For automatic conversions: the typed word, normalized, to learn as an exception.
        let exception: String?
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
        var verdict = verdict(for: strokes, layouts: layouts)
        // Only a space converts right away: punctuation after a word is too often code or a path
        // (src/, jwt-), so the word waits and converts along with the next one.
        if verdict == .convert, layouts.current.text(for: boundary) != " " {
            verdict = .undecided
        }
        guard verdict == .convert else {
            remember(TypedWord(strokes: strokes, trailing: [boundary], verdict: verdict, layoutID: layouts.current.id))
            return .pass
        }
        return convertAutomatically(strokes, boundary: boundary, layouts: layouts)
    }

    /// Return or Enter ends the line. A word that converts is retyped and the key pressed again
    /// after it (the app may send the message right away), so nothing of the line is kept for an undo.
    private mutating func finishLine(with key: KeyStroke, layouts: LayoutPair) -> EngineOutput {
        defer { reset() }
        guard convertsOnReturn, !overflowed, !word.isEmpty, verdict(for: word, layouts: layouts) == .convert else {
            return .pass
        }
        let segment = pendingStrokes(layouts: layouts) + word
        guard let original = layouts.current.text(for: segment), let inserted = layouts.other.text(for: segment) else {
            return .pass
        }
        self.layouts = layouts.swapped
        let replacement = Replacement(deleteCount: original.count, text: inserted, layoutID: layouts.other.id, followUpKey: key)
        return EngineOutput(suppressesEvent: true, replacement: replacement)
    }

    private func verdict(for strokes: [KeyStroke], layouts: LayoutPair) -> Verdict {
        guard isAutomatic, let detector, let typedLanguage = layouts.current.language,
              let otherLanguage = layouts.other.language, let typed = layouts.current.text(for: strokes),
              let other = layouts.other.text(for: strokes) else { return .keep }
        return detector.verdict(typed: typed, in: typedLanguage, other: other, in: otherLanguage, exceptions: exceptions)
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
            exception: layouts.current.text(for: strokes).map(WordText.normalized)
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
    /// last word, else ask for the selection.
    private mutating func doubleShift() -> EngineOutput {
        guard let layouts else { return .pass }
        if let conversion = lastConversion {
            return undo(conversion, layouts: layouts)
        }
        if !word.isEmpty {
            return convertByHand(word, layouts: layouts)
        }
        if let last = history.last, last.layoutID == layouts.current.id {
            let output = convertByHand(last.allStrokes, layouts: layouts)
            history = [TypedWord(strokes: last.strokes, trailing: last.trailing, verdict: nil, layoutID: layouts.other.id)]
            return output
        }
        return EngineOutput(convertsSelection: true)
    }

    private mutating func convertByHand(_ strokes: [KeyStroke], layouts: LayoutPair) -> EngineOutput {
        guard let typed = layouts.current.text(for: strokes), let other = layouts.other.text(for: strokes) else {
            return .pass
        }
        self.layouts = layouts.swapped
        lastConversion = Conversion(original: typed, insertedCount: other.count, fromLayoutID: layouts.current.id, exception: nil)
        return EngineOutput(replacement: Replacement(deleteCount: typed.count, text: other, layoutID: layouts.other.id))
    }

    private mutating func undo(_ conversion: Conversion, layouts: LayoutPair) -> EngineOutput {
        lastConversion = nil
        guard conversion.fromLayoutID == layouts.other.id else {
            reset()
            return .pass
        }
        self.layouts = layouts.swapped
        if var last = history.popLast() {
            if last.layoutID == layouts.current.id {
                last.layoutID = layouts.other.id
                last.verdict = .keep
            }
            history = [last]
        }
        if let exception = conversion.exception {
            exceptions.insert(exception)
        }
        let replacement = Replacement(deleteCount: conversion.insertedCount, text: conversion.original, layoutID: conversion.fromLayoutID)
        return EngineOutput(replacement: replacement, learnedException: conversion.exception)
    }
}
