import XCTest

final class WorkoutLoggerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()
    }

    /// Regression coverage for the `.grouping(.never)` fix: typing digits into
    /// the Weight/Reps fields must replace the value exactly, not duplicate
    /// digits via SwiftUI's live number reformatting.
    func testWeightAndRepsKeyboardInputDoesNotDuplicateDigits() throws {
        app.tabBars.buttons["History"].tap()

        let firstWorkoutRow = app.buttons["workoutRow-0"]
        XCTAssertTrue(firstWorkoutRow.waitForExistence(timeout: 5), "Expected a seeded workout to be visible in History")
        firstWorkoutRow.tap()

        let editWorkoutButton = app.buttons["editWorkoutButton"]
        XCTAssertTrue(editWorkoutButton.waitForExistence(timeout: 5))
        editWorkoutButton.tap()

        let setRow = app.buttons.matching(identifier: "setRow-0").firstMatch
        XCTAssertTrue(setRow.waitForExistence(timeout: 5))
        setRow.tap()

        let weightField = app.textFields["weightField-0"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        replaceText(in: weightField, with: "185")
        XCTAssertEqual(weightField.value as? String, "185")

        let repsField = app.textFields["repsField-0"]
        XCTAssertTrue(repsField.waitForExistence(timeout: 5))
        replaceText(in: repsField, with: "12")
        XCTAssertEqual(repsField.value as? String, "12")
    }

    /// Regression coverage for the Option B "Expandable Card" mockup: Volume,
    /// Elapsed, and (when active) Rest must render as a single stat-strip row
    /// rather than three stacked LabeledContent rows.
    func testSessionStatsStripShowsVolumeAndElapsedInOneRow() throws {
        app.tabBars.buttons["History"].tap()

        let addWorkoutMenuButton = app.buttons["addWorkoutMenuButton"]
        XCTAssertTrue(addWorkoutMenuButton.waitForExistence(timeout: 5))
        addWorkoutMenuButton.tap()

        let logWorkoutMenuItem = app.buttons["logWorkoutMenuItem"]
        XCTAssertTrue(logWorkoutMenuItem.waitForExistence(timeout: 5))
        logWorkoutMenuItem.tap()

        let statsStrip = app.otherElements["sessionStatsStrip"]
        XCTAssertTrue(statsStrip.waitForExistence(timeout: 5), "Expected the Session stats strip on a new (non-editing) workout")

        // SwiftUI may merge each cell's accessibilityElement(children: .ignore) into a
        // staticText rather than an "other" element, so match by identifier across any type.
        let volumeCell = app.descendants(matching: .any).matching(identifier: "statStripCell-Volume").firstMatch
        let elapsedCell = app.descendants(matching: .any).matching(identifier: "statStripCell-Elapsed").firstMatch
        XCTAssertTrue(volumeCell.exists)
        XCTAssertTrue(elapsedCell.exists)

        // Volume and Elapsed must sit in the same row (shared vertical band), not stacked.
        XCTAssertEqual(volumeCell.frame.minY, elapsedCell.frame.minY, accuracy: 1.0)

        // No active rest timer on a fresh workout, so the Rest cell should not render.
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "statStripCell-Rest").firstMatch.exists)
    }

    /// Regression coverage for removing the manual workout date field: the
    /// logger infers date/time from the session's start and end instead of
    /// letting the user pick one, on both the new-workout and edit-workout
    /// paths.
    func testWorkoutLoggerDoesNotShowADateField() throws {
        app.tabBars.buttons["History"].tap()

        let addWorkoutMenuButton = app.buttons["addWorkoutMenuButton"]
        XCTAssertTrue(addWorkoutMenuButton.waitForExistence(timeout: 5))
        addWorkoutMenuButton.tap()

        let logWorkoutMenuItem = app.buttons["logWorkoutMenuItem"]
        XCTAssertTrue(logWorkoutMenuItem.waitForExistence(timeout: 5))
        logWorkoutMenuItem.tap()

        XCTAssertTrue(app.textFields["Workout name"].waitForExistence(timeout: 5), "Expected the new-workout logger to appear")
        assertNoDateField()

        app.buttons["Discard"].tap()
        app.buttons["Discard Draft"].tap()

        let firstWorkoutRow = app.buttons["workoutRow-0"]
        XCTAssertTrue(firstWorkoutRow.waitForExistence(timeout: 5), "Expected a seeded workout to be visible in History")
        firstWorkoutRow.tap()

        let editWorkoutButton = app.buttons["editWorkoutButton"]
        XCTAssertTrue(editWorkoutButton.waitForExistence(timeout: 5))
        editWorkoutButton.tap()

        XCTAssertTrue(app.textFields["Workout name"].waitForExistence(timeout: 5), "Expected the edit-workout logger to appear")
        assertNoDateField()
    }

    private func assertNoDateField() {
        XCTAssertEqual(app.datePickers.count, 0, "The workout logger should not expose a date picker")
        let dateLabel = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Date")).firstMatch
        XCTAssertFalse(dateLabel.exists, "The workout logger should not show a standalone Date field")
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        if let existing = field.value as? String, !existing.isEmpty {
            let deleteKeys = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            field.typeText(deleteKeys)
        }
        field.typeText(text)
    }
}
