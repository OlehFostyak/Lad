import Foundation
import LadCore

/// Loads the bundled word lists off the main thread.
enum DictionaryLoader {
    /// Contents/Resources/Dictionaries; debug builds also take `--resources DIR` (an unbundled run).
    static func directory(arguments: [String] = CommandLine.arguments) -> URL? {
        #if DEBUG
        if let index = arguments.firstIndex(of: "--resources"), arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: arguments[index + 1]).appending(path: "Dictionaries")
        }
        #endif
        return Bundle.main.resourceURL?.appending(path: "Dictionaries")
    }

    static func load(from directory: URL) async throws -> [LanguageModel] {
        try await Task.detached(priority: .utility) {
            try Language.allCases.map { language in
                let tsv = try String(contentsOf: directory.appending(path: "\(language.rawValue).tsv"), encoding: .utf8)
                return try LanguageModel(language: language, tsv: tsv)
            }
        }.value
    }
}
