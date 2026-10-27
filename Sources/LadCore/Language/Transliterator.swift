/// Ukrainian in Latin letters by the official national system (Cabinet of Ministers resolution
/// No. 55 of 27 January 2010): for names of people, files and links.
public enum Transliterator {
    private static let letters: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "h", "ґ": "g", "д": "d", "е": "e", "є": "ie", "ж": "zh",
        "з": "z", "и": "y", "і": "i", "ї": "i", "й": "i", "к": "k", "л": "l", "м": "m", "н": "n",
        "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts",
        "ч": "ch", "ш": "sh", "щ": "shch", "ь": "", "ю": "iu", "я": "ia",
    ]
    /// These letters are spelled differently at the start of a word.
    private static let initialLetters: [Character: String] = ["є": "ye", "ї": "yi", "й": "y", "ю": "yu", "я": "ya"]
    private static let apostrophes: Set<Character> = ["'", "\u{2019}", "\u{02BC}"]

    /// The text in Latin letters; characters that are not Ukrainian letters stay. Nil when the text
    /// has no Ukrainian letters.
    public static func ukrainianToLatin(_ text: String) -> String? {
        let characters = Array(text)
        guard characters.contains(where: isUkrainianLetter) else { return nil }
        var result = ""
        for index in characters.indices {
            let character = characters[index]
            if apostrophes.contains(character), isInsideWord(index, characters) { continue }
            guard let lower = character.lowercased().first, let latin = latin(for: lower, at: index, in: characters) else {
                result.append(character)
                continue
            }
            result += cased(latin, from: character, inUppercaseWord: isInUppercaseWord(index, characters))
        }
        return result
    }

    private static func latin(for letter: Character, at index: Int, in characters: [Character]) -> String? {
        guard let latin = letters[letter] else { return nil }
        if isWordStart(index, characters), let initial = initialLetters[letter] {
            return initial
        }
        // "зг" is "zgh", so it is not read as "ж".
        if letter == "г", index > 0, characters[index - 1].lowercased() == "з" {
            return "gh"
        }
        return latin
    }

    private static func cased(_ latin: String, from character: Character, inUppercaseWord: Bool) -> String {
        guard character.isUppercase else { return latin }
        if inUppercaseWord { return latin.uppercased() }
        return latin.prefix(1).uppercased() + latin.dropFirst()
    }

    private static func isUkrainianLetter(_ character: Character) -> Bool {
        Language.ukrainian.isLetter(character)
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        isUkrainianLetter(character) || apostrophes.contains(character)
    }

    private static func isWordStart(_ index: Int, _ characters: [Character]) -> Bool {
        index == 0 || !isWordCharacter(characters[index - 1])
    }

    private static func isInsideWord(_ index: Int, _ characters: [Character]) -> Bool {
        index > 0 && index < characters.count - 1
            && isUkrainianLetter(characters[index - 1]) && isUkrainianLetter(characters[index + 1])
    }

    /// Whether the word around the letter is in capitals (two letters or more): ЩУКА → SHCHUKA.
    private static func isInUppercaseWord(_ index: Int, _ characters: [Character]) -> Bool {
        var start = index
        while start > 0, isWordCharacter(characters[start - 1]) { start -= 1 }
        var end = index
        while end < characters.count - 1, isWordCharacter(characters[end + 1]) { end += 1 }
        let letters = characters[start...end].filter(isUkrainianLetter)
        return letters.count > 1 && letters.allSatisfy(\.isUppercase)
    }
}

/// Cycles the case of a text: lowercase → UPPERCASE → Title Case → lowercase.
public enum CaseCycle {
    /// The next case; nil when the text has no letters.
    public static func next(_ text: String) -> String? {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return nil }
        if letters.allSatisfy({ !$0.isUppercase }) {
            return text.uppercased()
        }
        if letters.allSatisfy({ !$0.isLowercase }) {
            let title = titleCased(text)
            // A text whose title case is its capitals (one-letter words) goes on to lowercase.
            return title == text ? text.lowercased() : title
        }
        return text.lowercased()
    }

    /// Every word's first letter capitalized and the rest lowercase; words start after whitespace.
    static func titleCased(_ text: String) -> String {
        var result = ""
        var atWordStart = true
        for character in text {
            if character.isLetter {
                result += atWordStart ? character.uppercased() : character.lowercased()
                atWordStart = false
            } else {
                result.append(character)
                atWordStart = character.isWhitespace || atWordStart && !character.isLetter
            }
        }
        return result
    }
}
