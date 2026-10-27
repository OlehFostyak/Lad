import Foundation
import Testing
@testable import LadCore

@Suite("Word text")
struct WordTextTests {
    @Test("English cores", arguments: [
        ("hello,", "hello"), ("(word)", "word"), ("<this", "this"), ("don't", "don't"), ("'quoted'", "quoted"),
        ("Hello!", "hello"), ("[jxe", "jxe"),
    ])
    func englishCores(text: String, core: String) {
        #expect(WordText.core(of: text, in: .english) == core)
    }

    @Test("Not English words", arguments: [",elm", "a''b", "'", "", "x1", "привіт"])
    func notEnglish(text: String) {
        #expect(WordText.core(of: text, in: .english) == nil)
    }

    @Test("Ukrainian cores", arguments: [("м’ята", "м'ята"), ("Привіт!", "привіт"), ("«слово»", "слово"), ("сім'я", "сім'я")])
    func ukrainianCores(text: String, core: String) {
        #expect(WordText.core(of: text, in: .ukrainian) == core)
    }

    @Test("Ukrainian never wraps a word in apostrophes", arguments: ["'зі'", "п'", "'ять", "hello"])
    func notUkrainian(text: String) {
        #expect(WordText.core(of: text, in: .ukrainian) == nil)
    }

    @Test("Word characters")
    func wordCharacters() {
        #expect(WordText.isWordCharacter("'", in: .english))
        #expect(WordText.isWordCharacter("ʼ", in: .ukrainian))
        #expect(WordText.isWordCharacter("X", in: .english))
        #expect(!WordText.isWordCharacter("х", in: .english))
        #expect(WordText.isWordCharacter("Ґ", in: .ukrainian))
        #expect(!WordText.isWordCharacter("1", in: .ukrainian))
    }

    @Test("Normalization lowercases and folds apostrophes")
    func normalizes() {
        #expect(WordText.normalized("М’ЯТА") == "м'ята")
        #expect(WordText.normalized("Сімʼя") == "сім'я")
    }
}

@Suite("Language model")
struct LanguageModelTests {
    @Test("Parses word-count lines and skips comments and blank lines")
    func parses() throws {
        let model = try LanguageModel(language: .english, tsv: "# header\nhello\t3\n\nworld\t1\n")
        #expect(model.wordCount == 2)
        #expect(model.contains("hello"))
        let frequency = try #require(model.logFrequency(of: "hello"))
        #expect(abs(frequency - log(0.75)) < 1e-9)
        #expect(model.logFrequency(of: "nope") == nil)
    }

    @Test("Rejects malformed lines", arguments: ["hello", "hello\tx", "hello\t0", "привіт\t3", "he llo\t2", "a\tb\tc"])
    func rejectsMalformedLines(line: String) {
        #expect(throws: LanguageModel.LoadError.malformedLine(1)) {
            try LanguageModel(language: .english, tsv: line)
        }
    }

    @Test("Rejects a list without words")
    func rejectsEmptyList() {
        #expect(throws: LanguageModel.LoadError.empty) {
            try LanguageModel(language: .english, tsv: "# only a comment\n")
        }
    }

    @Test("Real words spell better than keyboard mash")
    func scoresSpelling() throws {
        let english = try #require(Fixture.models.first { $0.language == .english })
        let ukrainian = try #require(Fixture.models.first { $0.language == .ukrainian })
        #expect(english.spellingScore(of: "keyboard") > english.spellingScore(of: "ghbdsn"))
        #expect(ukrainian.spellingScore(of: "привітання") > ukrainian.spellingScore(of: "щшгзкх"))
        #expect(english.spellingLogProbability(of: "кирилиця") == -.infinity)
    }

    @Test("The bundled word lists load")
    func loadsBundledLists() {
        #expect(Fixture.models.count == 2)
        for model in Fixture.models {
            #expect(model.wordCount > 40_000)
        }
    }

    @Test("Alphabets and one-letter words")
    func alphabets() {
        #expect(Language.english.alphabet.count == 26)
        #expect(Language.ukrainian.alphabet.count == 33)
        #expect(Language.ukrainian.singleLetterWords.contains("я"))
        #expect(Language.english.isLetter("Q"))
        #expect(!Language.english.isLetter("ß"))
    }
}
