import Foundation

/// Word frequencies and a character model of spellings for one language.
public struct LanguageModel: Sendable {
    public enum LoadError: Error, Equatable {
        /// A line that is not `word<TAB>count` with a word of the language and a positive count.
        case malformedLine(Int)
        case empty
    }

    public let language: Language
    private let counts: [String: UInt32]
    private let logTotal: Double
    private let spelling: CharacterModel

    /// Parses `word<TAB>count` lines; blank lines and `#` comments are skipped.
    public init(language: Language, tsv: String) throws(LoadError) {
        var counts: [String: UInt32] = [:]
        for (index, line) in tsv.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.isEmpty || line.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2, let count = UInt32(fields[1]), count > 0 else {
                throw .malformedLine(index + 1)
            }
            let word = WordText.normalized(String(fields[0]))
            guard WordText.isWord(word, in: language) else { throw .malformedLine(index + 1) }
            counts[word] = (counts[word] ?? 0).addingReportingOverflow(count).overflow ? .max : (counts[word] ?? 0) + count
        }
        guard !counts.isEmpty else { throw .empty }
        self.init(language: language, counts: counts)
    }

    public init(language: Language, counts: [String: UInt32]) {
        self.language = language
        self.counts = counts
        let total = counts.values.reduce(0.0) { $0 + Double($1) }
        self.logTotal = log(max(total, 1))
        self.spelling = CharacterModel(language: language, counts: counts)
    }

    public var wordCount: Int { counts.count }

    public func contains(_ word: String) -> Bool {
        counts[word] != nil
    }

    /// Natural log of the word's share of running text; nil when the word is not listed.
    public func logFrequency(of word: String) -> Double? {
        counts[word].map { log(Double($0)) - logTotal }
    }

    /// Natural log of the spelling's probability under the character model, end of word included.
    public func spellingLogProbability(of word: String) -> Double {
        spelling.logProbability(of: word)
    }

    /// The spelling log probability per symbol (letters plus the end of word): how word-like it looks.
    public func spellingScore(of word: String) -> Double {
        spellingLogProbability(of: word) / Double(word.count + 1)
    }
}

/// An interpolated character trigram model of spellings, trained on the listed words, each weighted
/// by log(1 + count) so frequent words count more without drowning the rest.
struct CharacterModel: Sendable {
    private static let trigramWeight = 0.6
    private static let bigramWeight = 0.25
    private static let unigramWeight = 0.1
    private static let uniformWeight = 0.05
    /// Symbol 0 marks the start and the end of a word, 1 is the apostrophe, letters follow.
    private static let boundary = 0

    private let symbols: [Character: Int]
    private let size: Int
    private let trigrams: [Double]
    private let bigrams: [Double]
    private let unigrams: [Double]
    private let trigramContexts: [Double]
    private let bigramContexts: [Double]
    private let unigramTotal: Double

    init(language: Language, counts: [String: UInt32]) {
        var symbols: [Character: Int] = [WordText.apostrophe: 1]
        for (offset, letter) in language.alphabet.enumerated() {
            symbols[letter] = offset + 2
        }
        let size = language.alphabet.count + 2
        var trigrams = [Double](repeating: 0, count: size * size * size)
        var bigrams = [Double](repeating: 0, count: size * size)
        var unigrams = [Double](repeating: 0, count: size)
        for (word, count) in counts {
            guard let path = Self.path(of: word, symbols: symbols) else { continue }
            let weight = log(1 + Double(count))
            for index in 2..<path.count {
                let (a, b, c) = (path[index - 2], path[index - 1], path[index])
                trigrams[(a * size + b) * size + c] += weight
                bigrams[b * size + c] += weight
                unigrams[c] += weight
            }
        }
        var trigramContexts = [Double](repeating: 0, count: size * size)
        var bigramContexts = [Double](repeating: 0, count: size)
        for context in 0..<(size * size) {
            trigramContexts[context] = trigrams[(context * size)..<((context + 1) * size)].reduce(0, +)
        }
        for context in 0..<size {
            bigramContexts[context] = bigrams[(context * size)..<((context + 1) * size)].reduce(0, +)
        }
        self.symbols = symbols
        self.size = size
        self.trigrams = trigrams
        self.bigrams = bigrams
        self.unigrams = unigrams
        self.trigramContexts = trigramContexts
        self.bigramContexts = bigramContexts
        self.unigramTotal = unigrams.reduce(0, +)
    }

    /// Natural log probability of the spelling; -infinity when it has characters outside the alphabet.
    func logProbability(of word: String) -> Double {
        guard let path = Self.path(of: word, symbols: symbols) else { return -.infinity }
        var total = 0.0
        for index in 2..<path.count {
            total += log(probability(path[index - 2], path[index - 1], path[index]))
        }
        return total
    }

    /// P(c | a b), interpolated over the orders whose context was seen, so it always sums to one.
    private func probability(_ a: Int, _ b: Int, _ c: Int) -> Double {
        var probability = Self.uniformWeight / Double(size)
        var weight = Self.uniformWeight
        let trigramContext = trigramContexts[a * size + b]
        if trigramContext > 0 {
            probability += Self.trigramWeight * trigrams[(a * size + b) * size + c] / trigramContext
            weight += Self.trigramWeight
        }
        let bigramContext = bigramContexts[b]
        if bigramContext > 0 {
            probability += Self.bigramWeight * bigrams[b * size + c] / bigramContext
            weight += Self.bigramWeight
        }
        if unigramTotal > 0 {
            probability += Self.unigramWeight * unigrams[c] / unigramTotal
            weight += Self.unigramWeight
        }
        return probability / weight
    }

    /// Start, start, the word's symbols, end; nil for a character outside the alphabet.
    private static func path(of word: String, symbols: [Character: Int]) -> [Int]? {
        var path = [boundary, boundary]
        path.reserveCapacity(word.count + 3)
        for character in word {
            guard let symbol = symbols[character] else { return nil }
            path.append(symbol)
        }
        path.append(boundary)
        return path
    }
}
