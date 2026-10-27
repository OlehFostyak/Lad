/// Fixes of letter case typed by accident.
public enum CaseFix {
    /// Fewer letters than this are left alone: short capitals are usually abbreviations (IDs, PRs).
    static let minimumLetters = 4

    /// "ПРивіт" → "Привіт", "HEllo," → "Hello,": two capitals, then only lowercase letters. Other
    /// characters stay where they are. Nil when the text does not look like that.
    public static func twoInitialCapitals(_ text: String, in language: Language) -> String? {
        let letters = Array(text.filter(language.isLetter))
        guard letters.count >= minimumLetters, letters[0].isUppercase, letters[1].isUppercase,
              letters.dropFirst(2).allSatisfy(\.isLowercase) else { return nil }
        var seenLetters = 0
        return String(text.map { character -> Character in
            guard language.isLetter(character) else { return character }
            seenLetters += 1
            guard seenLetters == 2, let lower = character.lowercased().first else { return character }
            return lower
        })
    }
}
