/// The two languages Lad tells apart: English for Latin layouts, Ukrainian for Cyrillic ones.
public enum Language: String, Sendable, CaseIterable {
    case english = "en"
    case ukrainian = "uk"

    private static let englishAlphabet = Array("abcdefghijklmnopqrstuvwxyz")
    private static let ukrainianAlphabet = Array("абвгґдеєжзиіїйклмнопрстуфхцчшщьюя")
    private static let englishLetters = Set(englishAlphabet)
    private static let ukrainianLetters = Set(ukrainianAlphabet)

    /// The lowercase alphabet; the character model numbers its symbols in this order.
    public var alphabet: [Character] {
        switch self {
        case .english: Self.englishAlphabet
        case .ukrainian: Self.ukrainianAlphabet
        }
    }

    /// One-letter words. A pending single letter converts only into one of these.
    public var singleLetterWords: Set<String> {
        switch self {
        case .english: ["a", "i"]
        case .ukrainian: ["а", "в", "є", "ж", "з", "і", "й", "о", "у", "я"]
        }
    }

    /// Whether the character, in either case, is a letter of the alphabet.
    public func isLetter(_ character: Character) -> Bool {
        let letters = self == .english ? Self.englishLetters : Self.ukrainianLetters
        if letters.contains(character) { return true }
        let lowercased = character.lowercased()
        return lowercased.count == 1 && letters.contains(Character(lowercased))
    }
}
