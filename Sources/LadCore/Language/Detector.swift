import Foundation

/// The detector's decision about one typed word.
public enum Verdict: Sendable, Equatable {
    /// The word fits the layout it was typed in.
    case keep
    /// The word was meant for the other layout.
    case convert
    /// Too short or too close to call alone; it converts along with the next word if that one converts.
    case undecided
}

/// Detector thresholds, in natural-log units.
public struct DetectorConfig: Sendable, Equatable {
    /// How much more likely the other layout's word must be than the typed one (5 ≈ 150×).
    public var margin: Double
    /// The margin for other words of `shortLength` letters or fewer.
    public var shortMargin: Double
    public var shortLength: Int
    /// Extra margin when the typed text is itself a listed word: real words are protected harder.
    public var listedMargin: Double
    /// Short of the margin by less than this, a longer word is undecided rather than kept.
    public var undecidedBand: Double
    /// Natural log of the share of running text missing from each word list.
    public var unlistedLogShare: [Language: Double]
    /// Lad converts into an unlisted word only if it has at least this many letters...
    public var unlistedMinimumLength: Int
    /// ...and spells at least this well (log probability per symbol).
    public var unlistedMinimumScore: Double
    /// A word fixed by hand that is not listed is learned when it spells at least this well: real
    /// slang and names do (кринж, Фостяк), keyboard mash does not (йячмцф).
    public var learnableMinimumScore: Double
    /// Live switching: a word converts while typed once it has this many letters...
    public var liveMinimumLength: Int
    /// ...and the words the other layout's letters begin are this much more likely than the typed
    /// letters as the beginning of an unlisted word.
    public var liveMargin: Double

    public init(
        margin: Double, shortMargin: Double, shortLength: Int, listedMargin: Double, undecidedBand: Double,
        unlistedLogShare: [Language: Double], unlistedMinimumLength: Int, unlistedMinimumScore: Double,
        learnableMinimumScore: Double, liveMinimumLength: Int, liveMargin: Double
    ) {
        self.margin = margin
        self.shortMargin = shortMargin
        self.shortLength = shortLength
        self.listedMargin = listedMargin
        self.undecidedBand = undecidedBand
        self.unlistedLogShare = unlistedLogShare
        self.unlistedMinimumLength = unlistedMinimumLength
        self.unlistedMinimumScore = unlistedMinimumScore
        self.learnableMinimumScore = learnableMinimumScore
        self.liveMinimumLength = liveMinimumLength
        self.liveMargin = liveMargin
    }

    public static let standard = DetectorConfig(
        margin: 5, shortMargin: 6, shortLength: 2, listedMargin: 2, undecidedBand: 3,
        unlistedLogShare: [.english: log(0.03), .ukrainian: log(0.1)],
        unlistedMinimumLength: 5, unlistedMinimumScore: -2.6, learnableMinimumScore: -3.5,
        liveMinimumLength: 4, liveMargin: 10
    )
}

/// The scores behind a verdict, for tuning and tests.
public struct Evaluation: Sendable, Equatable {
    /// Log probability of the typed text in its layout's language; -infinity when it is no word.
    public let typedScore: Double
    /// Log probability of the other layout's word; nil when Lad never converts into it.
    public let otherScore: Double?
    /// The advantage the other word needed.
    public let margin: Double
    public let verdict: Verdict

    static let keep = Evaluation(typedScore: 0, otherScore: nil, margin: 0, verdict: .keep)
}

/// Decides whether a typed word was meant for the other keyboard layout: it compares how likely
/// the word is in the language of the layout it was typed in with how likely its twin (the same
/// keys in the other layout) is in the other language.
public struct Detector: Sendable {
    /// Latin code and shell tokens, and tech acronyms typed lowercase, whose keys spell a common
    /// Ukrainian word (db → ви, ns → ті, src → ікс, csv → сім). They never convert alone, only
    /// along with a following word that converts.
    public static let codeTokens: Set<String> = [
        "db", "ns", "nb", "vb", "nt", "ps", "sp", "lt", "ws", "ne", "jq", "ecs", "src", "csv", "jwt", "otp", "hsl",
    ]

    public let config: DetectorConfig
    private let models: [Language: LanguageModel]

    public init(models: [LanguageModel], config: DetectorConfig = .standard) {
        self.config = config
        self.models = Dictionary(models.map { ($0.language, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The verdict on `typed` (what the keys typed in the user's layout) against `other` (what the
    /// same keys type in the other layout). `exceptions` holds normalized typed words the user
    /// turned back before.
    /// `capsLocked`: Caps Lock typed the whole word, so its capitals say nothing about it.
    public func verdict(
        typed: String, in typedLanguage: Language, other: String, in otherLanguage: Language,
        exceptions: Set<String> = [], capsLocked: Bool = false
    ) -> Verdict {
        evaluate(
            typed: typed, in: typedLanguage, other: other, in: otherLanguage, exceptions: exceptions, capsLocked: capsLocked
        ).verdict
    }

    public func evaluate(
        typed: String, in typedLanguage: Language, other: String, in otherLanguage: Language,
        exceptions: Set<String> = [], capsLocked: Bool = false
    ) -> Evaluation {
        guard let typedModel = models[typedLanguage], let otherModel = models[otherLanguage],
              let otherWord = WordText.core(of: other, in: otherLanguage),
              !exceptions.contains(WordText.normalized(typed)),
              capsLocked || Self.hasPlainCase(typed, in: typedLanguage) else {
            return .keep
        }
        let (typedScore, typedIsListed) = score(ofTyped: typed, in: typedModel)
        guard let otherScore = convertibleScore(of: otherWord, in: otherModel) else {
            return Evaluation(typedScore: typedScore, otherScore: nil, margin: 0, verdict: .keep)
        }
        let isShort = otherWord.count <= config.shortLength
        let margin = (isShort ? config.shortMargin : config.margin) + (typedIsListed ? config.listedMargin : 0)
        let advantage = otherScore - typedScore
        let typedHasSymbols = typed.contains { !typedLanguage.isLetter($0) }
        let verdict: Verdict
        if otherWord.count == 1 || !typed.contains(where: typedLanguage.isLetter) || (isShort && typedHasSymbols) {
            // A single letter, keys that type only symbols here ("][" is "їх", "}}" is "ЇЇ") or a
            // short word with a symbol ("{e" is "Ху"): too common in code to convert alone.
            verdict = advantage > 0 ? .undecided : .keep
        } else if advantage >= margin {
            let isCodeToken = typedLanguage == .english && Self.codeTokens.contains(WordText.normalized(typed))
            verdict = isCodeToken ? .undecided : .convert
        } else if advantage >= (isShort ? 0 : margin - config.undecidedBand) {
            verdict = .undecided
        } else {
            verdict = .keep
        }
        return Evaluation(typedScore: typedScore, otherScore: otherScore, margin: margin, verdict: verdict)
    }

    /// Live switching: whether the word being typed converts before it ends. Its letters so far
    /// must begin no listed word of their language, and the same keys must begin listed words of
    /// the other language far likelier than these letters are as the start of an unlisted word.
    /// Letters only (a bracket or comma is too often code), plain case, never what begins a code
    /// token or a word the user turned back.
    public func convertsEarly(
        typed: String, in typedLanguage: Language, other: String, in otherLanguage: Language, exceptions: Set<String> = []
    ) -> Bool {
        guard let typedModel = models[typedLanguage], let otherModel = models[otherLanguage],
              typed.count >= config.liveMinimumLength, typed.allSatisfy(typedLanguage.isLetter),
              Self.hasPlainCase(typed, in: typedLanguage) else { return false }
        let typedPrefix = WordText.normalized(typed)
        let otherPrefix = WordText.normalized(other)
        guard typedModel.prefixLogFrequency(of: typedPrefix) == nil,
              !(typedLanguage == .english && Self.codeTokens.contains { $0.hasPrefix(typedPrefix) }),
              !exceptions.contains(where: { $0.hasPrefix(typedPrefix) }),
              let otherFrequency = otherModel.prefixLogFrequency(of: otherPrefix) else { return false }
        let typedScore = (config.unlistedLogShare[typedLanguage] ?? log(0.05)) + typedModel.prefixSpellingLogProbability(of: typedPrefix)
        return otherFrequency - typedScore >= config.liveMargin
    }

    /// Whether a pending undecided word converts along with the converted word after it.
    public func convertsAlong(typed: String, in typedLanguage: Language, other: String, in otherLanguage: Language) -> Bool {
        guard let typedModel = models[typedLanguage], let otherModel = models[otherLanguage],
              let otherWord = WordText.core(of: other, in: otherLanguage) else { return false }
        if otherWord.count == 1 {
            let typedWord = WordText.core(of: typed, in: typedLanguage)
            let typedIsWord = typedWord.map { typedLanguage.singleLetterWords.contains($0) } ?? false
            return otherLanguage.singleLetterWords.contains(otherWord) && !typedIsWord
        }
        guard let otherScore = convertibleScore(of: otherWord, in: otherModel) else { return false }
        return otherScore > score(ofTyped: typed, in: typedModel).score
    }

    /// Whether the word inside `text` is in the language's word list.
    public func isListed(_ text: String, in language: Language) -> Bool {
        guard let word = WordText.core(of: text, in: language) else { return false }
        return models[language]?.contains(word) ?? false
    }

    /// Whether the word inside `text`, listed or not, spells like a word of the language: at least
    /// three letters that the character model finds as likely as the words Lad converts into.
    public func looksLikeWord(_ text: String, in language: Language) -> Bool {
        spells(text, in: language, atLeast: config.unlistedMinimumScore)
    }

    /// Whether a word fixed by hand may be learned in this spelling: listed, or at least three
    /// letters that spell like the language's words, as slang and names do.
    public func isLearnable(_ text: String, in language: Language) -> Bool {
        isListed(text, in: language) || spells(text, in: language, atLeast: config.learnableMinimumScore)
    }

    private func spells(_ text: String, in language: Language, atLeast score: Double) -> Bool {
        guard let word = WordText.core(of: text, in: language), word.filter(language.isLetter).count >= 3,
              let model = models[language] else { return false }
        return model.spellingScore(of: word) >= score
    }

    /// Words are typed lowercase or capitalized; ALL CAPS and camelCase are acronyms and code (RFC, TVs).
    public static func hasPlainCase(_ typed: String, in language: Language) -> Bool {
        typed.filter(language.isLetter).dropFirst().allSatisfy { !$0.isUppercase }
    }

    /// The typed text as a word of its language: itself, or its core when that is a listed word
    /// ("hello," → hello). Punctuation around an unlisted core is no evidence for the typed layout
    /// ("vf." is "маю", not "vf").
    private func score(ofTyped typed: String, in model: LanguageModel) -> (score: Double, isListed: Bool) {
        let word = WordText.normalized(typed)
        if WordText.isWord(word, in: model.language) {
            if let frequency = model.logFrequency(of: word) { return (frequency, true) }
            return (unlistedScore(of: word, in: model), false)
        }
        if let core = WordText.core(of: typed, in: model.language), let frequency = model.logFrequency(of: core) {
            return (frequency, true)
        }
        return (-.infinity, false)
    }

    /// The score of a word Lad may convert into: listed, or unlisted but long and word-like.
    private func convertibleScore(of word: String, in model: LanguageModel) -> Double? {
        if let frequency = model.logFrequency(of: word) { return frequency }
        guard word.count >= config.unlistedMinimumLength,
              model.spellingScore(of: word) >= config.unlistedMinimumScore else { return nil }
        return unlistedScore(of: word, in: model)
    }

    private func unlistedScore(of word: String, in model: LanguageModel) -> Double {
        (config.unlistedLogShare[model.language] ?? log(0.05)) + model.spellingLogProbability(of: word)
    }
}
