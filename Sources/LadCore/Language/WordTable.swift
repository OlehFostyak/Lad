import Foundation

/// The words of one language and their counts, sorted by their UTF-8 bytes and packed into one
/// block: the app maps it straight from its bundle, so the list costs no heap and no parsing.
/// Looking a word up and totalling the words that start with a prefix are binary searches.
///
/// The block, little-endian with 8-byte aligned sections: "LADW", the word count, the byte count
/// and a zero (UInt32 each); where each word ends in the bytes (UInt32); each word's count
/// (UInt32); the total count of the words before each index, and of all words last (UInt64); the
/// words' bytes, back to back.
struct WordTable: Sendable {
    static let magic = UInt32(littleEndian: 0x5744_414C)

    /// Collects words in any order; a word added twice counts the sum.
    struct Builder {
        private var bytes: [UInt8] = []
        private var ends: [Int] = []
        private var counts: [UInt32] = []

        /// Room for about this many words, so a big list does not regrow its index.
        mutating func reserveCapacity(words: Int) {
            ends.reserveCapacity(words)
            counts.reserveCapacity(words)
        }

        mutating func add(_ word: String, count: UInt32) {
            bytes += word.utf8
            ends.append(bytes.count)
            counts.append(count)
        }

        func build() -> WordTable {
            let starts = [0] + ends.dropLast()
            var order = Array(counts.indices)
            var sortedBytes: [UInt8] = []
            var sortedEnds: [UInt32] = []
            var sortedCounts: [UInt32] = []
            sortedBytes.reserveCapacity(bytes.count)
            bytes.withUnsafeBytes { all in
                order.sort { compare(all.rebased(starts[$0]..<ends[$0]), all.rebased(starts[$1]..<ends[$1])) < 0 }
                var previous: Range<Int>?
                for index in order {
                    let range = starts[index]..<ends[index]
                    if let previous, compare(all.rebased(previous), all.rebased(range)) == 0 {
                        let (sum, overflow) = sortedCounts[sortedCounts.count - 1].addingReportingOverflow(counts[index])
                        sortedCounts[sortedCounts.count - 1] = overflow ? .max : sum
                        continue
                    }
                    sortedBytes += all.rebased(range)
                    sortedEnds.append(UInt32(sortedBytes.count))
                    sortedCounts.append(counts[index])
                    previous = range
                }
            }
            var block = Data()
            block.reserveCapacity(Layout(words: sortedCounts.count, bytes: sortedBytes.count).length)
            for field in [WordTable.magic, UInt32(sortedCounts.count), UInt32(sortedBytes.count), 0] {
                block.appendLittleEndian(field)
            }
            sortedEnds.forEach { block.appendLittleEndian($0) }
            block.padToEightBytes()
            sortedCounts.forEach { block.appendLittleEndian($0) }
            block.padToEightBytes()
            var total: UInt64 = 0
            block.appendLittleEndian(total)
            for count in sortedCounts {
                total += UInt64(count)
                block.appendLittleEndian(total)
            }
            block += sortedBytes
            block.padToEightBytes()
            // The block was just built to the layout, so it reads back.
            return WordTable(block: block)!
        }
    }

    /// Where the sections of a block with this many words and bytes start, and its length.
    private struct Layout {
        let ends: Int
        let counts: Int
        let totals: Int
        let bytes: Int
        let length: Int

        init(words: Int, bytes byteCount: Int) {
            ends = 16
            counts = ends + (words * 4).roundedUpToEight
            totals = counts + (words * 4).roundedUpToEight
            bytes = totals + (words + 1) * 8
            length = bytes + byteCount.roundedUpToEight
        }
    }

    /// The packed block, which `storage` may start with (more data can follow it).
    let storage: Data
    let count: Int
    private let layout: Layout

    /// Reads a block made by `Builder`; nil when `block` does not start with a well-formed one.
    init?(block: Data) {
        guard block.count >= 16 else { return nil }
        let (magic, words, byteCount) = block.withUnsafeBytes { raw in
            (raw.littleEndian(UInt32.self, at: 0), Int(raw.littleEndian(UInt32.self, at: 4)), Int(raw.littleEndian(UInt32.self, at: 8)))
        }
        let layout = Layout(words: words, bytes: byteCount)
        guard magic == Self.magic, block.count >= layout.length else { return nil }
        // Every word must end inside the bytes and after the one before, or lookups would read
        // outside the block.
        let wellFormed = block.withUnsafeBytes { raw in
            var previous = 0
            for index in 0..<words {
                let end = Int(raw.littleEndian(UInt32.self, at: layout.ends + index * 4))
                guard end > previous else { return false }
                previous = end
            }
            return previous == byteCount
        }
        guard wellFormed else { return nil }
        self.storage = block.prefix(layout.length)
        self.count = words
        self.layout = layout
    }

    /// The length of the packed block.
    var length: Int { layout.length }

    var total: UInt64 {
        storage.withUnsafeBytes { $0.littleEndian(UInt64.self, at: layout.totals + count * 8) }
    }

    func count(of word: String) -> UInt32? {
        var word = word
        return word.withUTF8 { key in
            storage.withUnsafeBytes { raw in
                let needle = UnsafeRawBufferPointer(key)
                let index = firstIndex(in: 0..<count) { compare(self.word(at: $0, in: raw), needle) >= 0 }
                guard index < count, compare(self.word(at: index, in: raw), needle) == 0 else { return nil }
                return raw.littleEndian(UInt32.self, at: layout.counts + index * 4)
            }
        }
    }

    /// How many words start with `prefix` and their total count; every word for an empty prefix.
    func totals(startingWith prefix: String) -> (words: Int, count: UInt64) {
        var prefix = prefix
        return prefix.withUTF8 { key in
            storage.withUnsafeBytes { raw in
                let needle = UnsafeRawBufferPointer(key)
                // The words with the prefix come right after the words below it, and before the
                // first word whose beginning is above it.
                let lower = firstIndex(in: 0..<count) { compare(word(at: $0, in: raw), needle) >= 0 }
                let upper = firstIndex(in: lower..<count) {
                    compare(UnsafeRawBufferPointer(rebasing: word(at: $0, in: raw).prefix(needle.count)), needle) > 0
                }
                let below = raw.littleEndian(UInt64.self, at: layout.totals + lower * 8)
                return (upper - lower, raw.littleEndian(UInt64.self, at: layout.totals + upper * 8) - below)
            }
        }
    }

    /// Every word with its count, in byte order.
    func forEach(_ body: (String, UInt32) -> Void) {
        storage.withUnsafeBytes { raw in
            for index in 0..<count {
                body(String(decoding: word(at: index, in: raw), as: UTF8.self), raw.littleEndian(UInt32.self, at: layout.counts + index * 4))
            }
        }
    }

    private func word(at index: Int, in raw: UnsafeRawBufferPointer) -> UnsafeRawBufferPointer {
        let start = index == 0 ? 0 : Int(raw.littleEndian(UInt32.self, at: layout.ends + (index - 1) * 4))
        let end = Int(raw.littleEndian(UInt32.self, at: layout.ends + index * 4))
        return raw.rebased((layout.bytes + start)..<(layout.bytes + end))
    }

    /// The first index of `range` where `isAtOrAbove` holds; it must hold for a tail of the range.
    private func firstIndex(in range: Range<Int>, where isAtOrAbove: (Int) -> Bool) -> Int {
        var low = range.lowerBound
        var high = range.upperBound
        while low < high {
            let middle = low + (high - low) / 2
            if isAtOrAbove(middle) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }
}

/// Byte order: -1, 0 or 1 as `a` sorts before, with or after `b`. A prefix sorts first.
private func compare(_ a: UnsafeRawBufferPointer, _ b: UnsafeRawBufferPointer) -> Int {
    for index in 0..<min(a.count, b.count) where a[index] != b[index] {
        return a[index] < b[index] ? -1 : 1
    }
    return a.count == b.count ? 0 : (a.count < b.count ? -1 : 1)
}

extension UnsafeRawBufferPointer {
    func rebased(_ range: Range<Int>) -> UnsafeRawBufferPointer {
        UnsafeRawBufferPointer(rebasing: self[range])
    }

    func littleEndian<Value: FixedWidthInteger>(_ type: Value.Type, at offset: Int) -> Value {
        Value(littleEndian: loadUnaligned(fromByteOffset: offset, as: Value.self))
    }
}

extension Data {
    mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
        Swift.withUnsafeBytes(of: value.littleEndian) { self += $0 }
    }

    mutating func padToEightBytes() {
        self += [UInt8](repeating: 0, count: count.roundedUpToEight - count)
    }
}

extension Int {
    var roundedUpToEight: Int { (self + 7) / 8 * 8 }
}
