import Foundation
import LadCore

/// Loads the bundled word lists off the main thread.
enum DictionaryLoader {
    /// Where the lists are: packed in Contents/Resources/Dictionaries, or, for an unbundled debug
    /// run with `--resources DIR`, as the source tree's text lists.
    struct Source {
        let directory: URL
        let isPacked: Bool
    }

    static func source(arguments: [String] = CommandLine.arguments) -> Source? {
        #if DEBUG
        if let index = arguments.firstIndex(of: "--resources"), arguments.indices.contains(index + 1) {
            return Source(directory: URL(fileURLWithPath: arguments[index + 1]).appending(path: "Dictionaries"), isPacked: false)
        }
        #endif
        return Bundle.main.resourceURL.map { Source(directory: $0.appending(path: "Dictionaries"), isPacked: true) }
    }

    /// A packed list is mapped, not read: its pages stay file-backed, so the lists add almost
    /// nothing to Lad's memory, and nothing is parsed at launch.
    static func load(from source: Source) async throws -> [LanguageModel] {
        try await Task.detached(priority: .utility) {
            try Language.allCases.map { language in
                let file = source.directory.appending(path: language.rawValue)
                guard source.isPacked else {
                    let tsv = try String(contentsOf: file.appendingPathExtension("tsv"), encoding: .utf8)
                    return try LanguageModel(language: language, tsv: tsv)
                }
                let packed = try Data(contentsOf: file.appendingPathExtension("lad"), options: .alwaysMapped)
                return try LanguageModel(language: language, packed: packed)
            }
        }.value
    }
}
