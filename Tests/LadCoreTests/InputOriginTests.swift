import Testing
@testable import LadCore

@Suite("Programs typing")
struct InputOriginTests {
    private func presses(_ times: [Double]) -> [Bool] {
        var rhythm = TypingRhythm()
        return times.map { rhythm.isMachine(at: $0) }
    }

    @Test("A burst faster than a hand is a program's from its fifth press")
    func detectsBurst() {
        #expect(presses([0, 0.002, 0.004, 0.006, 0.008, 0.01]) == [false, false, false, false, true, true])
    }

    @Test("Human typing, even fast, with a rollover or delivered in a batch, is not")
    func keepsHumanTyping() {
        #expect(presses([0, 0.06, 0.12, 0.13, 0.19, 0.25]).allSatisfy { !$0 })
        #expect(presses([0, 0.004, 0.08, 0.084, 0.15]).allSatisfy { !$0 })
        #expect(presses([0, 0.02, 0.04, 0.06, 0.12, 0.14, 0.16]).allSatisfy { !$0 })
        #expect(presses([0, 0.1, 0.1, 0.1, 0.2, 0.3, 0.3]).allSatisfy { !$0 })
    }

    @Test("A program pacing its keys under 25 ms is caught from the fifth press")
    func detectsPacedTyping() {
        #expect(presses([0, 0.012, 0.024, 0.036, 0.048, 0.06]) == [false, false, false, false, true, true])
    }

    @Test("A pause ends a burst; time going backwards is no burst")
    func burstEnds() {
        #expect(presses([0, 0.002, 0.004, 0.006, 0.008, 0.5, 0.502]) == [false, false, false, false, true, false, false])
        #expect(presses([1, 0.999, 0.998, 0.997, 0.996, 0.995]).allSatisfy { !$0 })
    }

    @Test("Posted presses count as foreign only after enough of the user's own")
    func calibratesSourceFilter() {
        var filter = SourceFilter()
        let posted = InputOrigin(processID: 4242, time: 0)
        let keyboard = InputOrigin(processID: 0, time: 0)
        let beforeCalibration = filter.isForeign(posted)
        #expect(!beforeCalibration)
        let ownPresses = (0..<(SourceFilter.calibrationPresses - 1)).map { _ in filter.isForeign(keyboard) }
        #expect(!ownPresses.contains(true))
        #expect(!filter.isCalibrated)
        _ = filter.isForeign(keyboard)
        #expect(filter.isCalibrated)
        let afterCalibration = filter.isForeign(posted)
        #expect(afterCalibration)
    }

    @Test("When every press carries a process ID, nothing is foreign")
    func staysOffWhenUnreliable() {
        var filter = SourceFilter()
        let verdicts = (0..<100).map { _ in filter.isForeign(InputOrigin(processID: 151, time: 0)) }
        #expect(!verdicts.contains(true))
    }
}
