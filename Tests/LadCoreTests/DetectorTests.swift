import Testing
@testable import LadCore

@Suite("Detector")
struct DetectorTests {
    private let detector = Fixture.detector

    private func verdict(typedInUS typed: String) -> Verdict {
        detector.verdict(typed: typed, in: .english, other: Fixture.retype(typed, from: Fixture.us, to: Fixture.ua), in: .ukrainian)
    }

    private func verdict(typedInUA typed: String) -> Verdict {
        detector.verdict(typed: typed, in: .ukrainian, other: Fixture.retype(typed, from: Fixture.ua, to: Fixture.us), in: .english)
    }

    @Test("Ukrainian words typed in the U.S. layout convert", arguments: [
        ("ghbdsn", "привіт"), ("[jxe", "хочу"), ("lzre.", "дякую"), ("cmjujlys", "сьогодні"),
        ("v`znf", "м'ята"), ("erhf]yf", "україна"), ("yt", "не"), ("oj", "що"),
        // Words films rarely say, which the Wikipedia counts add.
        ("rsds", "ківі"), ("cvfhnajy", "смартфон"), ("yjen,er", "ноутбук"),
    ])
    func convertsUkrainian(typed: String, meant: String) {
        #expect(Fixture.retype(typed, from: Fixture.us, to: Fixture.ua) == meant)
        #expect(verdict(typedInUS: typed) == .convert)
    }

    @Test("English words and code typed in the U.S. layout never convert alone", arguments: [
        "hello", "world", "git", "commit", "the", "ls", "cd", "npm", "kubectl", "docker", "here",
        "README", "RFC", "iPhone", "useState", "src", "csv", "jwt",
    ])
    func keepsEnglish(typed: String) {
        #expect(verdict(typedInUS: typed) != .convert)
    }

    @Test("English words typed in the Ukrainian layout convert", arguments: [
        ("руддщ", "hello"), ("цщкдв", "world"), ("лунищфкв", "keyboard"), ("сщььше", "commit"), ("еру", "the"),
    ])
    func convertsEnglish(typed: String, meant: String) {
        #expect(Fixture.retype(typed, from: Fixture.ua, to: Fixture.us) == meant)
        #expect(verdict(typedInUA: typed) == .convert)
    }

    @Test("Ukrainian words typed in the Ukrainian layout stay", arguments: [
        "привіт", "хочу", "дякую", "україна", "сьогодні", "м'ята", "що", "не", "ґанок",
    ])
    func keepsUkrainian(typed: String) {
        #expect(verdict(typedInUA: typed) != .convert)
    }

    @Test("Short or symbol-only typing waits for the next word", arguments: ["z", "db", "][", "{e", "}}"])
    func waitsForNextWord(typed: String) {
        #expect(verdict(typedInUS: typed) == .undecided)
    }

    @Test("Exceptions keep the word")
    func respectsExceptions() {
        let verdict = detector.verdict(typed: "Ghbdsn", in: .english, other: "Привіт", in: .ukrainian, exceptions: ["ghbdsn"])
        #expect(verdict == .keep)
    }

    @Test("The evaluation explains the verdict")
    func explainsVerdict() throws {
        let evaluation = detector.evaluate(typed: "ghbdsn", in: .english, other: "привіт", in: .ukrainian)
        let otherScore = try #require(evaluation.otherScore)
        #expect(otherScore - evaluation.typedScore >= evaluation.margin)
        #expect(evaluation.verdict == .convert)
    }

    @Test("Undecided words convert along only into real words")
    func convertsAlong() {
        #expect(detector.convertsAlong(typed: "z", in: .english, other: "я", in: .ukrainian))
        #expect(!detector.convertsAlong(typed: "a", in: .english, other: "ф", in: .ukrainian))
        #expect(detector.convertsAlong(typed: "db", in: .english, other: "ви", in: .ukrainian))
        #expect(!detector.convertsAlong(typed: "the", in: .english, other: "еру", in: .ukrainian))
    }

    @Test("Without models nothing converts")
    func keepsWithoutModels() {
        let empty = Detector(models: [])
        #expect(empty.verdict(typed: "ghbdsn", in: .english, other: "привіт", in: .ukrainian) == .keep)
        #expect(!empty.convertsAlong(typed: "z", in: .english, other: "я", in: .ukrainian))
    }
}
