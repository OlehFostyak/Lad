import Foundation

/// The modifier keys Lad looks at.
public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)
    public static let capsLock = Modifiers(rawValue: 1 << 5)

    /// Modifiers that turn a key press into a shortcut instead of text.
    public static let shortcut: Modifiers = [.control, .option, .command, .function]
}

/// What the event tap reports to the engine.
public enum InputEvent: Sendable, Equatable {
    case keyDown(keyCode: UInt16, modifiers: Modifiers, isRepeat: Bool)
    /// The held modifiers changed; `time` is in seconds on a monotonic clock.
    case modifiersChanged(Modifiers, time: TimeInterval)
    /// The caret or the focus moved: a click, an app switch, a secure field.
    case reset
}

/// Delete `deleteCount` characters before the caret, type `text`, press `followUpKey` if any (the
/// Return that ended the word), then select layout `layoutID`.
public struct Replacement: Sendable, Equatable {
    public let deleteCount: Int
    public let text: String
    public let layoutID: String
    public let followUpKey: KeyStroke?

    public init(deleteCount: Int, text: String, layoutID: String, followUpKey: KeyStroke? = nil) {
        self.deleteCount = deleteCount
        self.text = text
        self.layoutID = layoutID
        self.followUpKey = followUpKey
    }
}

/// What the app does in response to one input event.
public struct EngineOutput: Sendable, Equatable {
    /// Drop the event: the replacement retypes its character.
    public var suppressesEvent: Bool
    public var replacement: Replacement?
    /// A typed word the user turned back after an automatic conversion: never convert it again.
    public var learnedException: String?
    /// A typed word the user fixed by hand: always convert it from now on.
    public var learnedWord: String?
    /// A learned word to drop again (its fix was turned back).
    public var forgottenWord: String?
    /// Nothing typed to fix: convert the selected text instead.
    public var convertsSelection: Bool
    /// The replacement turns the last fix back.
    public var isUndo: Bool

    public init(
        suppressesEvent: Bool = false, replacement: Replacement? = nil, learnedException: String? = nil,
        learnedWord: String? = nil, forgottenWord: String? = nil, convertsSelection: Bool = false, isUndo: Bool = false
    ) {
        self.suppressesEvent = suppressesEvent
        self.replacement = replacement
        self.learnedException = learnedException
        self.learnedWord = learnedWord
        self.forgottenWord = forgottenWord
        self.convertsSelection = convertsSelection
        self.isUndo = isUndo
    }

    public static let pass = EngineOutput()
}

/// The layout in use and the one Lad converts into; their languages differ.
public struct LayoutPair: Sendable, Equatable {
    public let current: LayoutTable
    public let other: LayoutTable

    public init?(current: LayoutTable, other: LayoutTable) {
        guard let currentLanguage = current.language, let otherLanguage = other.language,
              currentLanguage != otherLanguage else { return nil }
        self.current = current
        self.other = other
    }

    private init(unchecked current: LayoutTable, other: LayoutTable) {
        self.current = current
        self.other = other
    }

    public var swapped: LayoutPair {
        LayoutPair(unchecked: other, other: current)
    }

    /// The first enabled layout whose language differs from the current one's, paired with it.
    public static func choose(currentID: String, from enabled: [LayoutTable]) -> LayoutPair? {
        guard let current = enabled.first(where: { $0.id == currentID }) else { return nil }
        return enabled.lazy.compactMap { LayoutPair(current: current, other: $0) }.first
    }
}
