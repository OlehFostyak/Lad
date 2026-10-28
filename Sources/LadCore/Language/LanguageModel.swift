import Foundation

/// Word frequencies and a character model of spellings for one language.
public struct LanguageModel: Sendable {
    public enum LoadError: Error, Equatable {
        /// A line that is not `word<TAB>count` with a word of the language and a positive count.
        case malformedLine(Int)
        case empty
    }

    public let language: Language
    private let words: WordTable
    private let logTotal: Double
    private let spelling: CharacterModel

    /// Parses `word<TAB>count` lines; blank lines and `#` comments are skipped. The text is read in
    /// place, one line at a time, so loading leaves no copies of the list behind.
    public init(language: Language, tsv: String) throws(LoadError) {
        var builder = WordTable.Builder()
        var lineNumber = 0
        let text = tsv.utf8
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: UInt8(ascii: "\n")) ?? text.endIndex
            lineNumber += 1
            let line = tsv[lineStart..<lineEnd]
            lineStart = lineEnd == text.endIndex ? lineEnd : text.index(after: lineEnd)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let tab = line.utf8.firstIndex(of: UInt8(ascii: "\t")), let count = UInt32(line[line.index(after: tab)...]),
                  count > 0 else {
                throw .malformedLine(lineNumber)
            }
            let word = WordText.normalized(String(line[..<tab]))
            guard WordText.isWord(word, in: language) else { throw .malformedLine(lineNumber) }
            builder.add(word, count: count)
        }
        let words = builder.build()
        guard words.count > 0 else { throw .empty }
        self.init(language: language, words: words)
    }

    public init(language: Language, counts: [String: UInt32]) {
        var builder = WordTable.Builder()
        for (word, count) in counts {
            builder.add(word, count: count)
        }
        self.init(language: language, words: builder.build())
    }

    private init(language: Language, words: WordTable) {
        self.language = language
        self.words = words
        self.logTotal = log(max(Double(words.total), 1))
        self.spelling = CharacterModel(language: language, words: words)
    }

    public var wordCount: Int { words.count }

    public func contains(_ word: String) -> Bool {
        words.count(of: word) != nil
    }

    /// Natural log of the word's share of running text; nil when the word is not listed.
    public func logFrequency(of word: String) -> Double? {
        words.count(of: word).map { log(Double($0)) - logTotal }
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

    init(language: Language, words: WordTable) {
        var symbols: [Character: Int] = [WordText.apostrophe: 1]
        for (offset, letter) in language.alphabet.enumerated() {
            symbols[letter] = offset + 2
        }
        let size = language.alphabet.count + 2
        var trigrams = [Double](repeating: 0, count: size * size * size)
        var bigrams = [Double](repeating: 0, count: size * size)
        var unigrams = [Double](repeating: 0, count: size)
        words.forEach { word, count in
            guard let path = Self.path(of: word, symbols: symbols) else { return }
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
