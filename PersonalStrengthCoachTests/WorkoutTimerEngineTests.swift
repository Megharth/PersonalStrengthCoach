import XCTest
@testable import PersonalStrengthCoach

final class WorkoutTimerEngineTests: XCTestCase {
    func testNormalElapsedMinutesRoundsToWholeMinutes() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(42 * 60)

        XCTAssertEqual(WorkoutTimerEngine.elapsedMinutes(start: start, end: end), 42)
    }

    func testElapsedMinutesFloorsPartialMinutesRatherThanRounding() {
        // 42m40s elapsed: a rounding (rather than flooring) implementation would
        // incorrectly report 43.
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(42 * 60 + 40)

        XCTAssertEqual(WorkoutTimerEngine.elapsedMinutes(start: start, end: end), 42)
    }

    func testElapsedMinutesFloorsAtOneWhenEndIsVeryCloseToStart() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(5)

        XCTAssertEqual(WorkoutTimerEngine.elapsedMinutes(start: start, end: end), 1)
    }

    func testElapsedMinutesFloorsAtOneWhenEndEqualsStart() {
        let start = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(WorkoutTimerEngine.elapsedMinutes(start: start, end: start), 1)
    }

    func testElapsedMinutesFloorsAtOneWhenEndIsBeforeStart() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(-120)

        XCTAssertEqual(WorkoutTimerEngine.elapsedMinutes(start: start, end: end), 1)
    }

    func testElapsedMinutesCapsAtTwoHundredFortyForMultiDaySpans() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(50 * 3_600)

        XCTAssertEqual(WorkoutTimerEngine.elapsedMinutes(start: start, end: end), 240)
    }

    func testElapsedMinutesAtExactlyOneMinuteBoundary() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(60)

        XCTAssertEqual(WorkoutTimerEngine.elapsedMinutes(start: start, end: end), 1)
    }

    func testElapsedMinutesAtExactlyTwoHundredFortyMinuteBoundary() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(240 * 60)

        XCTAssertEqual(WorkoutTimerEngine.elapsedMinutes(start: start, end: end), 240)
    }

    func testElapsedMinutesJustOverTwoHundredFortyMinutesIsCapped() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(241 * 60)

        XCTAssertEqual(WorkoutTimerEngine.elapsedMinutes(start: start, end: end), 240)
    }
}
