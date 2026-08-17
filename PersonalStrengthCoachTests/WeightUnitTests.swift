import XCTest
@testable import PersonalStrengthCoach

final class WeightUnitTests: XCTestCase {
    func testPoundsConvertToCanonicalKilograms() {
        XCTAssertEqual(WeightUnit.pounds.toKilograms(10), 4.5359237, accuracy: 0.000001)
    }

    func testKilogramRoundTripThroughPounds() {
        let kilograms = 82.5
        XCTAssertEqual(
            WeightUnit.pounds.toKilograms(WeightUnit.pounds.fromKilograms(kilograms)),
            kilograms,
            accuracy: 0.000001
        )
    }

    func testFormattingUsesSelectedUnit() {
        XCTAssertEqual(WeightUnit.kilograms.formattedWithUnit(20), "20 kg")
        XCTAssertEqual(WeightUnit.pounds.formattedWithUnit(20), "44.1 lb")
    }

    func testNonFiniteFormattingIsUnavailable() {
        XCTAssertEqual(WeightUnit.pounds.formattedWithUnit(.infinity), "— lb")
    }
}
