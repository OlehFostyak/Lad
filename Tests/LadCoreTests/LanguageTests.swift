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

@Suite("Word table")
struct WordTableTests {
    private static func table(_ counts: [(String, UInt32)]) -> WordTable {
        var builder = WordTable.Builder()
        for (word, count) in counts {
            builder.add(word, count: count)
        }
        return builder.build()
    }

    @Test("Looks words up and adds up repeated ones, saturating")
    func looksUp() {
        let table = Self.table([("привіт", 5), ("при", 2), ("hello", 1), ("привіт", 3), ("max", .max), ("max", 1)])
        #expect(table.count == 4)
        #expect(table.count(of: "привіт") == 8)
        #expect(table.count(of: "при") == 2)
        #expect(table.count(of: "hello") == 1)
        #expect(table.count(of: "max") == .max)
        #expect(table.count(of: "прив") == nil)
        #expect(table.count(of: "привітання") == nil)
        #expect(table.count(of: "") == nil)
    }

    @Test("Totals the words that start with a prefix")
    func totalsPrefixes() {
        let table = Self.table([("при", 2), ("привіт", 5), ("прийти", 3), ("про", 7), ("п'ять", 4), ("є", 1), ("їжа", 6)])
        #expect(table.totals(startingWith: "при") == (3, 10))
        #expect(table.totals(startingWith: "прив") == (1, 5))
        #expect(table.totals(startingWith: "пр") == (4, 17))
        #expect(table.totals(startingWith: "п") == (5, 21))
        #expect(table.totals(startingWith: "п'") == (1, 4))
        #expect(table.totals(startingWith: "привітання") == (0, 0))
        #expect(table.totals(startingWith: "ґ") == (0, 0))
        #expect(table.totals(startingWith: "ї") == (1, 6))
        #expect(table.totals(startingWith: "") == (7, 28))
        #expect(table.total == 28)
    }

    @Test("Visits every word once, in byte order")
    func visitsWords() {
        let table = Self.table([("b", 1), ("a", 2), ("ab", 3), ("a", 1)])
        var visited: [String] = []
        table.forEach { word, count in visited.append("\(word)=\(count)") }
        #expect(visited == ["a=3", "ab=3", "b=1"])
    }

    @Test("The bundled lists answer like a dictionary of their lines")
    func matchesLines() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/Dictionaries")
        let tsv = try String(contentsOf: directory.appending(path: "uk.tsv"), encoding: .utf8)
        var expected: [String: UInt32] = [:]
        for line in tsv.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            expected[String(fields[0]), default: 0] += try #require(UInt32(fields[1]))
        }
        let model = try LanguageModel(language: .ukrainian, tsv: tsv)
        #expect(model.wordCount == expected.count)
        let total = expected.values.reduce(0.0) { $0 + Double($1) }
        for (word, count) in expected.prefix(2_000) {
            let frequency = try #require(model.logFrequency(of: word))
            #expect(abs(frequency - log(Double(count) / total)) < 1e-9)
        }
    }
}
