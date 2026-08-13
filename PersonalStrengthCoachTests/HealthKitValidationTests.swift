import XCTest
@testable import PersonalStrengthCoach

final class HealthKitValidationTests: XCTestCase {
    func testRestingHeartRateValidationRejectsImpossibleValues() {
        XCTAssertTrue(HealthKitValidation.isValid(30, for: .restingHeartRate))
        XCTAssertTrue(HealthKitValidation.isValid(72, for: .restingHeartRate))
        XCTAssertTrue(HealthKitValidation.isValid(120, for: .restingHeartRate))
        XCTAssertFalse(HealthKitValidation.isValid(29.9, for: .restingHeartRate))
        XCTAssertFalse(HealthKitValidation.isValid(121, for: .restingHeartRate))
        XCTAssertFalse(HealthKitValidation.isValid(.nan, for: .restingHeartRate))
        XCTAssertFalse(HealthKitValidation.isValid(.infinity, for: .restingHeartRate))
    }

    func testHRVValidationRejectsImpossibleValues() {
        XCTAssertTrue(HealthKitValidation.isValid(1, for: .hrvSDNN))
        XCTAssertTrue(HealthKitValidation.isValid(65, for: .hrvSDNN))
        XCTAssertTrue(HealthKitValidation.isValid(200, for: .hrvSDNN))
        XCTAssertFalse(HealthKitValidation.isValid(0, for: .hrvSDNN))
        XCTAssertFalse(HealthKitValidation.isValid(-1, for: .hrvSDNN))
        XCTAssertFalse(HealthKitValidation.isValid(201, for: .hrvSDNN))
        XCTAssertFalse(HealthKitValidation.isValid(.nan, for: .hrvSDNN))
        XCTAssertFalse(HealthKitValidation.isValid(-.infinity, for: .hrvSDNN))
    }

    func testSleepValidationRejectsImpossibleDurations() {
        XCTAssertTrue(HealthKitValidation.isValid(0, for: .sleepHours))
        XCTAssertTrue(HealthKitValidation.isValid(7.5, for: .sleepHours))
        XCTAssertTrue(HealthKitValidation.isValid(16, for: .sleepHours))
        XCTAssertFalse(HealthKitValidation.isValid(-0.1, for: .sleepHours))
        XCTAssertFalse(HealthKitValidation.isValid(16.01, for: .sleepHours))
    }

    func testBodyMassValidationRejectsImpossibleValues() {
        XCTAssertTrue(HealthKitValidation.isValid(20, for: .bodyMassKg))
        XCTAssertTrue(HealthKitValidation.isValid(82.5, for: .bodyMassKg))
        XCTAssertTrue(HealthKitValidation.isValid(300, for: .bodyMassKg))
        XCTAssertFalse(HealthKitValidation.isValid(0, for: .bodyMassKg))
        XCTAssertFalse(HealthKitValidation.isValid(19.9, for: .bodyMassKg))
        XCTAssertFalse(HealthKitValidation.isValid(301, for: .bodyMassKg))
    }

    func testMedianHandlesEmptySingleOddAndEvenCounts() {
        XCTAssertNil(HealthKitValidation.median([]))
        XCTAssertEqual(HealthKitValidation.median([42]), 42)
        XCTAssertEqual(HealthKitValidation.median([3, 1, 2]), 2)
        XCTAssertEqual(HealthKitValidation.median([4, 1, 3, 2]), 2.5)
    }

    func testTrimmedMeanDropsTailsAndFallsBackForTinySamples() {
        XCTAssertEqual(HealthKitValidation.trimmedMean([10, 40, 50, 60, 200]), 50)
        XCTAssertEqual(HealthKitValidation.trimmedMean([10, 20]), 15)
        XCTAssertNil(HealthKitValidation.trimmedMean([]))
    }

    func testFilterValidDropsOutOfRangeAndPreservesOrder() {
        XCTAssertEqual(HealthKitValidation.filterValid([0, 50, 55, 999, 60], for: .restingHeartRate), [50, 55, 60])
    }

    func testAggregateFiltersInvalidValuesBeforeMedianAndReportsCount() {
        let aggregate = HealthKitValidation.aggregate([50, 55, 999, 60], for: .restingHeartRate)
        XCTAssertEqual(aggregate?.value, 55)
        XCTAssertEqual(aggregate?.sampleCount, 3)
    }

    func testAggregateReturnsNilWhenAllSamplesAreInvalid() {
        XCTAssertNil(HealthKitValidation.aggregate([500, 600], for: .hrvSDNN))
    }
}
