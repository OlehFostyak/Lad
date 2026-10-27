/// The writing system a keyboard layout types, judged by the letters on its keys.
public enum Script: String, Sendable {
    case latin
    case cyrillic
    case other
}

/// The characters one keyboard layout types for every key of the typing block, per Shift and
/// Caps Lock state.
public struct LayoutTable: Sendable, Equatable {
    /// A script needs at least this many letters on plain keys (U.S. has 26, Ukrainian 33).
    private static let minimumScriptLetters = 20

    public let id: String
    public let name: String
    public let script: Script
    private let characters: [KeyStroke: String]
    private let strokes: [Character: KeyStroke]

    public init(id: String, name: String, characters: [KeyStroke: String]) {
        self.id = id
        self.name = name
        self.characters = characters
        self.script = Self.script(of: characters)
        self.strokes = Self.strokes(typing: characters)
    }

    /// The language Lad models for the layout's script; nil when there is none.
    public var language: Language? {
        switch script {
        case .latin: .english
        case .cyrillic: .ukrainian
        case .other: nil
        }
    }

    public func text(for stroke: KeyStroke) -> String? {
        characters[stroke]
    }

    /// The text of the strokes in order; nil when one of them types nothing in this layout.
    public func text(for strokes: [KeyStroke]) -> String? {
        var result = ""
        for stroke in strokes {
            guard let text = characters[stroke] else { return nil }
            result += text
        }
        return result
    }

    /// The key that types `character`, preferring a plain key, then Shift, then Caps Lock.
    public func stroke(for character: Character) -> KeyStroke? {
        strokes[character]
    }

    private static func script(of characters: [KeyStroke: String]) -> Script {
        var latin = 0
        var cyrillic = 0
        for (stroke, text) in characters where !stroke.shift && !stroke.capsLock {
            for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
                switch scalar.value {
                case 0x41...0x5A, 0x61...0x7A: latin += 1
                case 0x0400...0x04FF: cyrillic += 1
                default: break
                }
            }
        }
        if latin >= minimumScriptLetters, latin > cyrillic { return .latin }
        if cyrillic >= minimumScriptLetters, cyrillic > latin { return .cyrillic }
        return .other
    }

    private static func strokes(typing characters: [KeyStroke: String]) -> [Character: KeyStroke] {
        // Simplest stroke first; the key code breaks ties so the table does not depend on hashing.
        func rank(_ stroke: KeyStroke) -> Int {
            ((stroke.capsLock ? 2 : 0) + (stroke.shift ? 1 : 0)) * 1_000 + Int(stroke.keyCode)
        }
        var result: [Character: KeyStroke] = [:]
        for stroke in characters.keys.sorted(by: { rank($0) < rank($1) }) {
            guard let text = characters[stroke], text.count == 1, let character = text.first else { continue }
            if result[character] == nil {
                result[character] = stroke
            }
        }
        return result
    }
}

/// A layout table as JSON (test fixtures, `lad-eval dump-layouts`): key code → the characters for
/// plain, Shift, Caps Lock and Shift + Caps Lock, "" where the key types nothing.
public struct LayoutSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let keys: [String: [String]]

    public init(id: String, name: String, keys: [String: [String]]) {
        self.id = id
        self.name = name
        self.keys = keys
    }
}

extension LayoutTable {
    public init(snapshot: LayoutSnapshot) {
        var characters: [KeyStroke: String] = [:]
        for (code, texts) in snapshot.keys {
            guard let keyCode = UInt16(code), KeyCode.typesText(keyCode) else { continue }
            for (stroke, text) in zip(KeyStroke.variants(of: keyCode), texts) where !text.isEmpty {
                characters[stroke] = text
            }
        }
        self.init(id: snapshot.id, name: snapshot.name, characters: characters)
    }

    public var snapshot: LayoutSnapshot {
        var keys: [String: [String]] = [:]
        for keyCode in KeyCode.typingBlock {
            let texts = KeyStroke.variants(of: keyCode).map { characters[$0] ?? "" }
            if texts.contains(where: { !$0.isEmpty }) {
                keys[String(keyCode)] = texts
            }
        }
        return LayoutSnapshot(id: id, name: name, keys: keys)
    }
}
