import Foundation
import Testing
@testable import LadCore

/// The user's two layouts (captured by `make fixtures`) and the bundled word lists.
enum Fixture {
    static let tables: [LayoutTable] = {
        guard let url = Bundle.module.url(forResource: "layouts", withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url),
              let snapshots = try? JSONDecoder().decode([LayoutSnapshot].self, from: data) else { return [] }
        return snapshots.map(LayoutTable.init(snapshot:))
    }()

    static var us: LayoutTable { tables.first { $0.id == "com.apple.keylayout.US" }! }
    static var ua: LayoutTable { tables.first { $0.script == .cyrillic }! }
    static var typingInUS: LayoutPair { LayoutPair(current: us, other: ua)! }
    static var typingInUA: LayoutPair { LayoutPair(current: ua, other: us)! }

    static let models: [LanguageModel] = {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/Dictionaries")
        return Language.allCases.compactMap { language in
            guard let tsv = try? String(contentsOf: directory.appending(path: "\(language.rawValue).tsv"), encoding: .utf8) else {
                return nil
            }
            return try? LanguageModel(language: language, tsv: tsv)
        }
    }()

    static let detector = Detector(models: models)

    /// What the keys that type `text` in `table` type in `other`.
    static func retype(_ text: String, from table: LayoutTable, to other: LayoutTable) -> String {
        other.text(for: text.compactMap { table.stroke(for: $0) }) ?? ""
    }
}

/// Drives an engine key by key, like a person at the keyboard.
struct Typist {
    var engine: LadEngine
    private var clock: TimeInterval = 0

    init(_ layouts: LayoutPair, automatic: Bool = true) {
        engine = LadEngine(layouts: layouts, detector: Fixture.detector)
        engine.isAutomatic = automatic
    }

    /// Presses the keys that type `text` in `table`, whatever the current layout; returns the
    /// outputs that did something.
    @discardableResult
    mutating func type(_ text: String, on table: LayoutTable) -> [EngineOutput] {
        var outputs: [EngineOutput] = []
        for character in text {
            guard let stroke = table.stroke(for: character) else {
                Issue.record("\(character) is not on \(table.name)")
                continue
            }
            let output = press(stroke.keyCode, stroke.shift ? .shift : [])
            if output != .pass { outputs.append(output) }
        }
        return outputs
    }

    @discardableResult
    mutating func press(_ keyCode: UInt16, _ modifiers: Modifiers = []) -> EngineOutput {
        engine.handle(.keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: false))
    }

    mutating func doubleShift() -> EngineOutput {
        clock += 10
        _ = engine.handle(.modifiersChanged(.shift, time: clock))
        _ = engine.handle(.modifiersChanged([], time: clock + 0.05))
        _ = engine.handle(.modifiersChanged(.shift, time: clock + 0.15))
        return engine.handle(.modifiersChanged([], time: clock + 0.2))
    }
}
