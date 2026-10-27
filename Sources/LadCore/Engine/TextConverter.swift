/// Text retyped in another layout.
public struct ConvertedText: Sendable, Equatable {
    public let text: String
    /// The layout the text is in now.
    public let layoutID: String
}

/// Converts arbitrary text, such as a selection, as if its keys had been pressed in the other layout.
public enum TextConverter {
    /// The text was typed in the layout whose letters it mostly uses; every character that layout
    /// types is retyped with the same key in the other layout, the rest stays. Nil when the text
    /// has no letters of either layout.
    public static func convert(_ text: String, layouts: LayoutPair) -> ConvertedText? {
        let currentLetters = letterCount(of: text, in: layouts.current)
        let otherLetters = letterCount(of: text, in: layouts.other)
        guard currentLetters + otherLetters > 0 else { return nil }
        let (source, target) = currentLetters >= otherLetters ? (layouts.current, layouts.other) : (layouts.other, layouts.current)
        var result = ""
        for character in text {
            if let stroke = source.stroke(for: character), let converted = target.text(for: stroke) {
                result += converted
            } else {
                result.append(character)
            }
        }
        return ConvertedText(text: result, layoutID: target.id)
    }

    private static func letterCount(of text: String, in table: LayoutTable) -> Int {
        guard let language = table.language else { return 0 }
        return text.reduce(0) { $0 + (language.isLetter($1) ? 1 : 0) }
    }
}
