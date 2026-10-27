/// Normalizes typed words and finds the word inside a run of typed characters.
public enum WordText {
    public static let apostrophe: Character = "'"
    private static let typographicApostrophes: Set<Character> = ["\u{2019}", "\u{02BC}"]
    /// Punctuation that may open a word ("(word", "<tag") and close one ("word,", "так?"). A comma
    /// or period in front of letters is not stripped: that is a Ukrainian б or ю typed in the U.S.
    /// layout. Ukrainian never wraps a word in apostrophes, so "'зі'" (typed as `ps`) is no word.
    private static let englishOpeners: Set<Character> = ["(", "[", "{", "<", "\"", "'", "`", "“", "‘"]
    private static let englishClosers: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}", ">", "\"", "'", "`", "”", "’", "…"]
    private static let ukrainianOpeners: Set<Character> = ["(", "[", "{", "\"", "«", "„", "“"]
    private static let ukrainianClosers: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}", "\"", "»", "”", "…"]

    /// Lowercased, with typographic apostrophes folded into '.
    public static func normalized(_ text: String) -> String {
        String(text.lowercased().map { typographicApostrophes.contains($0) ? apostrophe : $0 })
    }

    /// Whether the character can be part of a word in `language`: a letter or an apostrophe.
    public static func isWordCharacter(_ character: Character, in language: Language) -> Bool {
        character == apostrophe || typographicApostrophes.contains(character) || language.isLetter(character)
    }

    /// The word inside `text`: openers stripped from the front, closers from the back, normalized.
    /// Nil when what remains is not a word of `language`.
    public static func core(of text: String, in language: Language) -> String? {
        let openers = language == .english ? englishOpeners : ukrainianOpeners
        let closers = language == .english ? englishClosers : ukrainianClosers
        var characters = Substring(text)
        while let first = characters.first, openers.contains(first) {
            characters.removeFirst()
        }
        while let last = characters.last, closers.contains(last) {
            characters.removeLast()
        }
        let word = normalized(String(characters))
        return isWord(word, in: language) ? word : nil
    }

    /// Letters of `language`, with single apostrophes only between letters ("м'ята", "don't").
    public static func isWord(_ word: String, in language: Language) -> Bool {
        guard let first = word.first, let last = word.last, language.isLetter(first), language.isLetter(last) else {
            return false
        }
        var previousWasApostrophe = false
        for character in word {
            if character == apostrophe {
                if previousWasApostrophe { return false }
                previousWasApostrophe = true
            } else {
                guard language.isLetter(character) else { return false }
                previousWasApostrophe = false
            }
        }
        return true
    }
}
