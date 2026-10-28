/// The words of one language and their counts, sorted by their UTF-8 bytes. Looking a word up and
/// totalling the words that start with a prefix are both binary searches, and a word costs its
/// bytes and 16 bytes of index rather than a dictionary bucket and a string object.
struct WordTable: Sendable {
    /// Collects words in any order; a word added twice counts the sum.
    struct Builder {
        private var bytes: [UInt8] = []
        private var ends: [Int] = []
        private var counts: [UInt32] = []

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
            bytes.withUnsafeBufferPointer { all in
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
            var runningTotals: [UInt64] = [0]
            runningTotals.reserveCapacity(sortedCounts.count + 1)
            for count in sortedCounts {
                runningTotals.append(runningTotals[runningTotals.count - 1] + UInt64(count))
            }
            return WordTable(bytes: sortedBytes, ends: sortedEnds, counts: sortedCounts, runningTotals: runningTotals)
        }
    }

    /// The words back to back, in byte order.
    private let bytes: [UInt8]
    /// Where each word ends in `bytes`; it starts where the one before it ends.
    private let ends: [UInt32]
    private let counts: [UInt32]
    /// The total count of the words before each index, and of all words last: the total of a run
    /// of words is one subtraction.
    private let runningTotals: [UInt64]

    var count: Int { counts.count }
    var total: UInt64 { runningTotals[runningTotals.count - 1] }

    func count(of word: String) -> UInt32? {
        var word = word
        return word.withUTF8 { key in
            bytes.withUnsafeBufferPointer { all in
                let index = firstIndex(in: 0..<counts.count) { compare(self.word(at: $0, in: all), key) >= 0 }
                guard index < counts.count, compare(self.word(at: index, in: all), key) == 0 else { return nil }
                return counts[index]
            }
        }
    }

    /// How many words start with `prefix` and their total count; every word for an empty prefix.
    func totals(startingWith prefix: String) -> (words: Int, count: UInt64) {
        var prefix = prefix
        let range = prefix.withUTF8 { key in
            bytes.withUnsafeBufferPointer { all in
                // The words with the prefix come right after the words below it, and before the
                // first word whose beginning is above it.
                let lower = firstIndex(in: 0..<counts.count) { compare(word(at: $0, in: all), key) >= 0 }
                let upper = firstIndex(in: lower..<counts.count) {
                    compare(UnsafeBufferPointer(rebasing: word(at: $0, in: all).prefix(key.count)), key) > 0
                }
                return lower..<upper
            }
        }
        return (range.count, runningTotals[range.upperBound] - runningTotals[range.lowerBound])
    }

    /// Every word with its count, in byte order.
    func forEach(_ body: (String, UInt32) -> Void) {
        bytes.withUnsafeBufferPointer { all in
            for index in counts.indices {
                body(String(decoding: word(at: index, in: all), as: UTF8.self), counts[index])
            }
        }
    }

    private func word(at index: Int, in all: UnsafeBufferPointer<UInt8>) -> UnsafeBufferPointer<UInt8> {
        all.rebased((index == 0 ? 0 : Int(ends[index - 1]))..<Int(ends[index]))
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
private func compare(_ a: UnsafeBufferPointer<UInt8>, _ b: UnsafeBufferPointer<UInt8>) -> Int {
    for index in 0..<min(a.count, b.count) where a[index] != b[index] {
        return a[index] < b[index] ? -1 : 1
    }
    return a.count == b.count ? 0 : (a.count < b.count ? -1 : 1)
}

private extension UnsafeBufferPointer<UInt8> {
    func rebased(_ range: Range<Int>) -> UnsafeBufferPointer<UInt8> {
        UnsafeBufferPointer(rebasing: self[range])
    }
}
