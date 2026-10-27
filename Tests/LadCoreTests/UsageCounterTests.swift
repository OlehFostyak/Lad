import Foundation
import Testing
@testable import LadCore

@Suite("Usage counter")
struct UsageCounterTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv") ?? .current
        return calendar
    }

    private func day(_ value: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: value, hour: hour)) ?? .distantPast
    }

    @Test("Fixes add up per day and over the week")
    func countsDaysAndWeek() {
        var counter = UsageCounter()
        counter.record(on: day(27, hour: 9), calendar: calendar)
        counter.record(on: day(27, hour: 23), calendar: calendar)
        counter.record(on: day(25), calendar: calendar)
        #expect(counter.count(on: day(27), calendar: calendar) == 2)
        #expect(counter.count(on: day(26), calendar: calendar) == 0)
        #expect(counter.weekTotal(endingOn: day(27), calendar: calendar) == 3)
        #expect(counter.counts == ["2026-10-27": 2, "2026-10-25": 1])
    }

    @Test("Days older than a week drop out")
    func dropsOldDays() {
        var counter = UsageCounter(counts: ["2026-10-01": 9, "2026-10-21": 4, "2026-10-20": 5])
        counter.record(on: day(27), calendar: calendar)
        #expect(counter.counts == ["2026-10-21": 4, "2026-10-27": 1])
        #expect(counter.weekTotal(endingOn: day(27), calendar: calendar) == 5)
        #expect(counter.weekTotal(endingOn: day(30), calendar: calendar) == 1)
    }
}
