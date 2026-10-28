import Foundation
import LadCore

// lad-eval: offline tools for Lad's detector (never shipped in the app).
//
//   lad-eval dump-layouts
//       JSON snapshots of the enabled keyboard layouts, the test fixture (make fixtures).
//   lad-eval quality [--resources DIR] [--fixture FILE] [--top N] [--test-words DIR] [--code DIR]...
//       How often the top N words of each list convert when typed in the wrong layout and stay
//       when typed in the right one, by length and weighted by frequency. --test-words takes the
//       words from another Resources directory (to compare word lists on the same words). With
//       --code, every conversion inside source files typed in the Latin layout (ideally none).
//   lad-eval sweep [same options]
//       The headline numbers for a grid of detector thresholds.
//   lad-eval live [same options] [--unlisted FILE] [--live-length N --live-margin M]
//       Live switching for a grid of thresholds (or the one given, with code's early switches
//       listed): how many words typed in the wrong layout switch before their end and after how
//       many keys, and every early switch of a word typed in the right layout, of the unlisted
//       words in FILE (one per line, typed in their own layout) and of code.
//   lad-eval pack [--resources DIR] --out DIR
//       Packs each word list into DIR/<language>.lad, the form the app maps (make bundle).
//   lad-eval explain [--resources DIR] [--fixture FILE] WORD...
//       The scores behind the verdicts for words typed in the wrong and in the right layout.

struct EvalError: Error, CustomStringConvertible {
    let description: String
}

struct Options {
    var resources = URL(fileURLWithPath: "Resources")
    var fixture = URL(fileURLWithPath: "Tests/LadCoreTests/Fixtures/layouts.json")
    var top = 20_000
    /// Test words from these word lists instead of the ones the models load, to compare lists.
    var testWords: URL?
    var out: URL?
    var unlisted: URL?
    var liveLength: Int?
    var liveMargin: Double?
    var codeDirectories: [URL] = []
    var words: [String] = []

    init(_ arguments: ArraySlice<String>) throws {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            guard argument.hasPrefix("--") else {
                words.append(argument)
                continue
            }
            guard let value = iterator.next() else { throw EvalError(description: "\(argument) needs a value") }
            switch argument {
            case "--resources": resources = URL(fileURLWithPath: value)
            case "--fixture": fixture = URL(fileURLWithPath: value)
            case "--top": top = Int(value) ?? top
            case "--test-words": testWords = URL(fileURLWithPath: value)
            case "--out": out = URL(fileURLWithPath: value)
            case "--unlisted": unlisted = URL(fileURLWithPath: value)
            case "--live-length": liveLength = Int(value)
            case "--live-margin": liveMargin = Double(value)
            case "--code": codeDirectories.append(URL(fileURLWithPath: (value as NSString).expandingTildeInPath))
            default: throw EvalError(description: "unknown option \(argument)")
            }
        }
    }
}

/// Weighted and plain counts of hits.
struct Tally {
    var weight = 0.0
    var hitWeight = 0.0
    var count = 0
    var hits = 0

    mutating func add(weight: Double, hit: Bool) {
        self.weight += weight
        count += 1
        if hit {
            hitWeight += weight
            hits += 1
        }
    }

    mutating func merge(_ other: Tally) {
        weight += other.weight
        hitWeight += other.hitWeight
        count += other.count
        hits += other.hits
    }

    var share: Double { weight > 0 ? 100 * hitWeight / weight : 0 }

    var summary: String {
        guard count > 0 else { return "      -" }
        return String(format: "%6.2f%% of uses, %6.2f%% of %5d words", share, 100 * Double(hits) / Double(count), count)
    }
}

struct WordResult {
    var converted: [String: Tally] = [:]
    var kept: [String: Tally] = [:]
    var misses: [String] = []
    var falseConversions: [String] = []

    func converted(_ buckets: [String]) -> Tally {
        buckets.reduce(into: Tally()) { $0.merge(converted[$1] ?? Tally()) }
    }

    var falseConversionCount: Int { kept.values.reduce(0) { $0 + $1.count - $1.hits } }
}

/// Everything an evaluation needs, loaded once.
struct Corpus {
    let latin: LayoutTable
    let cyrillic: LayoutTable
    let models: [LanguageModel]
    let words: [Language: [(word: String, count: UInt32)]]
    let code: [String]

    init(_ options: Options) throws {
        let snapshots = try JSONDecoder().decode([LayoutSnapshot].self, from: Data(contentsOf: options.fixture))
        let tables = snapshots.map(LayoutTable.init(snapshot:))
        guard let latin = tables.first(where: { $0.language == .english }),
              let cyrillic = tables.first(where: { $0.language == .ukrainian }) else {
            throw EvalError(description: "\(options.fixture.path) needs a Latin and a Cyrillic layout")
        }
        var models: [LanguageModel] = []
        var words: [Language: [(word: String, count: UInt32)]] = [:]
        for language in Language.allCases {
            let path = "Dictionaries/\(language.rawValue).tsv"
            let tsv = try String(contentsOf: options.resources.appending(path: path), encoding: .utf8)
            models.append(try LanguageModel(language: language, tsv: tsv))
            let testTSV = try options.testWords.map { try String(contentsOf: $0.appending(path: path), encoding: .utf8) } ?? tsv
            words[language] = Self.topWords(testTSV, limit: options.top)
        }
        self.latin = latin
        self.cyrillic = cyrillic
        self.models = models
        self.words = words
        self.code = Self.sourceTexts(options.codeDirectories)
    }

    func home(_ language: Language) -> LayoutTable { language == .english ? latin : cyrillic }
    func away(_ language: Language) -> LayoutTable { language == .english ? cyrillic : latin }

    private static func topWords(_ tsv: String, limit: Int) -> [(word: String, count: UInt32)] {
        var result: [(String, UInt32)] = []
        for line in tsv.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            guard fields.count == 2, let count = UInt32(fields[1]) else { continue }
            result.append((String(fields[0]), count))
            if result.count == limit { break }
        }
        return result
    }

    private static func sourceTexts(_ directories: [URL]) -> [String] {
        let extensions: Set<String> = [
            "swift", "ts", "tsx", "js", "jsx", "vue", "py", "sh", "go", "rs", "json", "yml", "yaml", "md",
            "toml", "css", "scss", "html", "c", "h", "m", "sql", "kt", "java", "rb",
        ]
        var texts: [String] = []
        for directory in directories {
            let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
            for file in files where extensions.contains(file.pathExtension) {
                guard !file.path.contains("/.build/"), !file.path.contains("/node_modules/"),
                      let text = try? String(contentsOf: file, encoding: .utf8), text.utf8.count < 1_000_000 else { continue }
                texts.append(text)
            }
        }
        return texts
    }
}

extension KeyStroke {
    var modifiers: Modifiers {
        var modifiers: Modifiers = []
        if shift { modifiers.insert(.shift) }
        if capsLock { modifiers.insert(.capsLock) }
        return modifiers
    }
}

/// Types the strokes and a space; the replacement Lad would make, if any.
func typeWord(_ strokes: [KeyStroke], layouts: LayoutPair, detector: Detector) -> Replacement? {
    var engine = LadEngine(layouts: layouts, detector: detector)
    var replacement: Replacement?
    for stroke in strokes + [KeyStroke(keyCode: KeyCode.space)] {
        let output = engine.handle(.keyDown(keyCode: stroke.keyCode, modifiers: stroke.modifiers, isRepeat: false))
        replacement = output.replacement ?? replacement
    }
    return replacement
}

func lengthBucket(_ word: String) -> String {
    switch word.count {
    case 1: "1"
    case 2: "2"
    case 3...4: "3-4"
    default: "5+"
    }
}

func evaluateWords(_ language: Language, corpus: Corpus, detector: Detector) -> WordResult {
    let home = corpus.home(language)
    let away = corpus.away(language)
    guard let right = LayoutPair(current: home, other: away), let wrong = LayoutPair(current: away, other: home) else {
        return WordResult()
    }
    var result = WordResult()
    for (word, count) in corpus.words[language] ?? [] {
        let strokes = word.compactMap { home.stroke(for: $0) }
        guard strokes.count == word.count, let typedWrong = away.text(for: strokes) else { continue }
        let bucket = lengthBucket(word)
        let stayed = typeWord(strokes, layouts: right, detector: detector)
        result.kept[bucket, default: Tally()].add(weight: Double(count), hit: stayed == nil)
        if let stayed, result.falseConversions.count < 30 {
            result.falseConversions.append("\(word)→\(stayed.text.trimmingCharacters(in: .whitespaces))")
        }
        let hit = typeWord(strokes, layouts: wrong, detector: detector)?.text == word + " "
        result.converted[bucket, default: Tally()].add(weight: Double(count), hit: hit)
        if !hit, word.count > 1, result.misses.count < 40 {
            result.misses.append("\(typedWrong)(\(word))")
        }
    }
    return result
}

/// Feeds source files to the engine as if typed in the Latin layout; every conversion is a false one.
func evaluateCode(corpus: Corpus, detector: Detector, live: Bool = false) -> (words: Int, conversions: [String: Int]) {
    guard let pair = LayoutPair(current: corpus.latin, other: corpus.cyrillic) else { return (0, [:]) }
    var engine = LadEngine(layouts: pair, detector: detector)
    engine.convertsWhileTyping = live
    var conversions: [String: Int] = [:]
    var words = 0
    for text in corpus.code {
        engine.reset()
        var recent = ""
        for character in text {
            // A line break is a press of Return, which ends (and may convert) a word too.
            let lineStroke = character == "\n" ? KeyStroke(keyCode: KeyCode.returnKey) : nil
            guard character != "\t", let stroke = lineStroke ?? corpus.latin.stroke(for: character) else {
                _ = engine.handle(.reset)
                continue
            }
            if character == " " { words += 1 }
            let output = engine.handle(.keyDown(keyCode: stroke.keyCode, modifiers: stroke.modifiers, isRepeat: false))
            if let replacement = output.replacement {
                let typed = String(recent.suffix(replacement.deleteCount)) + String(character)
                conversions["\(typed)→\(replacement.text)", default: 0] += 1
                engine.currentLayoutDidChange(to: corpus.latin.id)
            }
            recent = String((recent + String(character)).suffix(64))
        }
    }
    return (words, conversions)
}

func report(_ language: Language, _ result: WordResult) {
    print("\n== \(language.rawValue) ==")
    for bucket in ["1", "2", "3-4", "5+"] {
        print("  len \(bucket.padding(toLength: 3, withPad: " ", startingAt: 0))  converts \(result.converted[bucket]?.summary ?? "-")")
        print("           stays    \(result.kept[bucket]?.summary ?? "-")")
    }
    print("  most frequent misses: \(result.misses.joined(separator: " "))")
    print("  false conversions: \(result.falseConversions.isEmpty ? "none" : result.falseConversions.joined(separator: " "))")
}

/// Types the word and a space with live switching on, like the app would show them: a key the
/// engine lets through types in the layout in use before it.
func typeLive(_ strokes: [KeyStroke], layouts: LayoutPair, detector: Detector) -> (screen: String, earlyAt: Int?) {
    var engine = LadEngine(layouts: layouts, detector: detector)
    engine.convertsWhileTyping = true
    var screen = ""
    var earlyAt: Int?
    for (index, stroke) in (strokes + [KeyStroke(keyCode: KeyCode.space)]).enumerated() {
        let table = engine.layouts?.current ?? layouts.current
        let output = engine.handle(.keyDown(keyCode: stroke.keyCode, modifiers: stroke.modifiers, isRepeat: false))
        if let replacement = output.replacement {
            screen.removeLast(min(replacement.deleteCount, screen.count))
            screen += replacement.text
            if index < strokes.count, earlyAt == nil { earlyAt = index + 1 }
        }
        if !output.suppressesEvent { screen += table.text(for: stroke) ?? "" }
    }
    return (screen, earlyAt)
}

func runLive(_ options: Options) throws {
    let corpus = try Corpus(options)
    let unlisted = try options.unlisted.map { url in
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { String($0.split(separator: "\t")[0]) }
    } ?? []
    print("len margin | wrong layout switch early (uses/words, mean keys) and end right | false early: right words, unlisted, code")
    let single = options.liveLength.flatMap { length in options.liveMargin.map { (length, $0) } }
    let baseline = single.map { _ in evaluateCode(corpus: corpus, detector: Detector(models: corpus.models)).conversions } ?? [:]
    for minimum in single.map({ [$0.0] }) ?? [3, 4] {
        for margin in single.map({ [$0.1] }) ?? [4.0, 6, 8, 10, 12] {
            var config = DetectorConfig.standard
            config.liveMinimumLength = minimum
            config.liveMargin = margin
            let detector = Detector(models: corpus.models, config: config)
            var line = String(format: "%2d %5.1f  |", minimum, margin)
            var falseRight = 0
            for language in [Language.ukrainian, .english] {
                let home = corpus.home(language)
                let away = corpus.away(language)
                guard let right = LayoutPair(current: home, other: away), let wrong = LayoutPair(current: away, other: home) else { continue }
                var early = Tally()
                var correct = Tally()
                var keys = 0
                for (word, count) in corpus.words[language] ?? [] where word.count >= minimum {
                    let strokes = word.compactMap { home.stroke(for: $0) }
                    guard strokes.count == word.count else { continue }
                    let typed = typeLive(strokes, layouts: wrong, detector: detector)
                    early.add(weight: Double(count), hit: typed.earlyAt != nil)
                    correct.add(weight: Double(count), hit: typed.screen == word + " ")
                    keys += typed.earlyAt ?? 0
                    if typeLive(strokes, layouts: right, detector: detector).earlyAt != nil { falseRight += 1 }
                }
                line += String(format: " %@ %5.1f%%/%5.1f%% %.1f keys, end %5.1f%% |", language.rawValue,
                               early.hitWeight / max(early.weight, 1) * 100, Double(early.hits) / Double(max(early.count, 1)) * 100,
                               Double(keys) / Double(max(early.hits, 1)), correct.hitWeight / max(correct.weight, 1) * 100)
            }
            var falseUnlisted: [String] = []
            if let pair = LayoutPair(current: corpus.cyrillic, other: corpus.latin) {
                for word in unlisted {
                    let strokes = word.compactMap { corpus.cyrillic.stroke(for: $0) }
                    guard strokes.count == word.count else { continue }
                    if typeLive(strokes, layouts: pair, detector: detector).earlyAt != nil { falseUnlisted.append(word) }
                }
            }
            let conversions = evaluateCode(corpus: corpus, detector: detector, live: true).conversions
            line += " \(falseRight) \(falseUnlisted.count)/\(unlisted.count) \(conversions.values.reduce(0, +))"
            if !falseUnlisted.isEmpty { line += "  e.g. " + falseUnlisted.prefix(8).joined(separator: " ") }
            print(line)
            if single != nil {
                for (conversion, count) in conversions.sorted(by: { $0.value > $1.value }) where count > baseline[conversion, default: 0] {
                    print("    \(count - baseline[conversion, default: 0])× \(conversion)")
                }
            }
        }
    }
}

func runPack(_ options: Options) throws {
    guard let out = options.out else { throw EvalError(description: "pack needs --out DIR") }
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for language in Language.allCases {
        let tsv = try String(contentsOf: options.resources.appending(path: "Dictionaries/\(language.rawValue).tsv"), encoding: .utf8)
        let model = try LanguageModel(language: language, tsv: tsv)
        let packed = model.packed()
        // The app refuses a pack that does not read back.
        _ = try LanguageModel(language: language, packed: packed)
        try packed.write(to: out.appending(path: "\(language.rawValue).lad"), options: .atomic)
        print("packed \(language.rawValue): \(model.wordCount) words, \(packed.count) bytes")
    }
}

func runQuality(_ options: Options) throws {
    let start = Date()
    let corpus = try Corpus(options)
    print(String(format: "loaded in %.2f s", Date().timeIntervalSince(start)))
    let detector = Detector(models: corpus.models)
    report(.ukrainian, evaluateWords(.ukrainian, corpus: corpus, detector: detector))
    report(.english, evaluateWords(.english, corpus: corpus, detector: detector))
    guard !corpus.code.isEmpty else { return }
    let (words, conversions) = evaluateCode(corpus: corpus, detector: detector)
    let total = conversions.values.reduce(0, +)
    print("\n== code (\(words) words) ==")
    print(String(format: "  false conversions: %d (%.3f per 1000 words)", total, 1000 * Double(total) / Double(max(words, 1))))
    for (pair, count) in conversions.sorted(by: { $0.value > $1.value }).prefix(40) {
        print("    \(count)× \(pair.replacingOccurrences(of: "\n", with: "⏎"))")
    }
}

func runSweep(_ options: Options) throws {
    let corpus = try Corpus(options)
    print("margin short listed band | uk 3+   uk 2    en 3+   en 2   | false: uk en code")
    for margin in [4.0, 5, 6, 7] {
        for shortMargin in [5.0, 6, 7, 8] {
            for listedMargin in [0.0, 2, 4] {
                var config = DetectorConfig.standard
                config.margin = margin
                config.shortMargin = shortMargin
                config.listedMargin = listedMargin
                let detector = Detector(models: corpus.models, config: config)
                let uk = evaluateWords(.ukrainian, corpus: corpus, detector: detector)
                let en = evaluateWords(.english, corpus: corpus, detector: detector)
                let code = evaluateCode(corpus: corpus, detector: detector).conversions.values.reduce(0, +)
                print(String(
                    format: "%5.1f %5.1f %6.1f %4.1f | %6.2f %6.2f %6.2f %6.2f | %4d %4d %4d",
                    margin, shortMargin, listedMargin, config.undecidedBand,
                    uk.converted(["3-4", "5+"]).share, uk.converted(["2"]).share,
                    en.converted(["3-4", "5+"]).share, en.converted(["2"]).share,
                    uk.falseConversionCount, en.falseConversionCount, code
                ))
            }
        }
    }
}

func runExplain(_ options: Options) throws {
    let corpus = try Corpus(options)
    let detector = Detector(models: corpus.models)
    for word in options.words {
        let language: Language = word.contains(where: Language.ukrainian.isLetter) ? .ukrainian : .english
        let home = corpus.home(language)
        let away = corpus.away(language)
        let strokes = word.compactMap { home.stroke(for: $0) }
        guard strokes.count == word.count, let wrong = away.text(for: strokes) else {
            print("\(word): not typeable in \(home.name)")
            continue
        }
        let otherLanguage: Language = language == .english ? .ukrainian : .english
        for (typed, typedLanguage, other, label) in [(wrong, otherLanguage, word, "wrong"), (word, language, wrong, "right")] {
            let e = detector.evaluate(typed: typed, in: typedLanguage, other: other, in: language == typedLanguage ? otherLanguage : language)
            let otherScore = e.otherScore.map { String(format: "%.2f", $0) } ?? "nil"
            print(String(format: "%@ %@ typed %@ (%.2f) other %@ (%@) margin %.1f → %@", word, label, typed, e.typedScore, other, otherScore, e.margin, "\(e.verdict)"))
        }
    }
}

@MainActor
func dumpLayouts() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(SystemLayouts.enabled().map(\.snapshot))
    FileHandle.standardOutput.write(data + Data("\n".utf8))
}

let arguments = CommandLine.arguments.dropFirst()
do {
    switch arguments.first {
    case "dump-layouts": try MainActor.assumeIsolated { try dumpLayouts() }
    case "quality": try runQuality(try Options(arguments.dropFirst()))
    case "sweep": try runSweep(try Options(arguments.dropFirst()))
    case "explain": try runExplain(try Options(arguments.dropFirst()))
    case "pack": try runPack(try Options(arguments.dropFirst()))
    case "live": try runLive(try Options(arguments.dropFirst()))
    default:
        throw EvalError(description: "usage: lad-eval dump-layouts | quality | sweep | explain WORD... | pack --out DIR [--resources DIR] [--fixture FILE] [--top N] [--test-words DIR] [--code DIR]")
    }
} catch {
    FileHandle.standardError.write(Data("lad-eval: \(error)\n".utf8))
    exit(1)
}
