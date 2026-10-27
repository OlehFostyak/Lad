import Foundation

/// How many fixes Lad made on each of the last seven days: numbers only.
public struct UsageCounter: Sendable, Equatable {
    public static let days = 7

    /// "2026-10-27" → fixes that day; only the last seven days are kept.
    public private(set) var counts: [String: Int]

    public init(counts: [String: Int] = [:]) {
        self.counts = counts
    }

    public mutating func record(on date: Date, calendar: Calendar = .current) {
        counts[Self.key(for: date, calendar: calendar), default: 0] += 1
        // Keys sort by date, so everything before the week's first day goes.
        guard let firstDay = calendar.date(byAdding: .day, value: -(Self.days - 1), to: date) else { return }
        let cutoff = Self.key(for: firstDay, calendar: calendar)
        counts = counts.filter { $0.key >= cutoff }
    }

    public func count(on date: Date, calendar: Calendar = .current) -> Int {
        counts[Self.key(for: date, calendar: calendar)] ?? 0
    }

    /// The seven days that end with `date`'s day.
    public func weekTotal(endingOn date: Date, calendar: Calendar = .current) -> Int {
        Self.week(endingOn: date, calendar: calendar).reduce(0) { $0 + count(on: $1, calendar: calendar) }
    }

    private static func week(endingOn date: Date, calendar: Calendar) -> [Date] {
        (0..<days).compactMap { calendar.date(byAdding: .day, value: -$0, to: date) }
    }

    private static func key(for date: Date, calendar: Calendar) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }
}
