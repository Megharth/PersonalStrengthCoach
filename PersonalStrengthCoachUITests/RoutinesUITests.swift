import XCTest

final class RoutinesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()
    }

    /// Regression coverage for moving "start from routine" out of the workout
    /// logger and onto the Routines list: swiping a routine row and tapping
    /// Start must open the logger pre-filled with that routine's exercises,
    /// and the logger itself must no longer expose its own routine picker.
    func testStartActionOnRoutineRowOpensPrefilledLogger() throws {
        app.tabBars.buttons["History"].tap()

        let addWorkoutMenuButton = app.buttons["addWorkoutMenuButton"]
        XCTAssertTrue(addWorkoutMenuButton.waitForExistence(timeout: 5))
        addWorkoutMenuButton.tap()

        let routinesMenuItem = app.buttons["routinesMenuItem"]
        XCTAssertTrue(routinesMenuItem.waitForExistence(timeout: 5))
        routinesMenuItem.tap()

        let newRoutineButton = app.buttons["New Routine"]
        XCTAssertTrue(newRoutineButton.waitForExistence(timeout: 5))
        newRoutineButton.tap()

        let nameField = app.textFields["Routine name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Push Day UI Test")

        app.buttons["Add exercise"].tap()
        let benchPress = app.buttons["Barbell Bench Press"]
        XCTAssertTrue(benchPress.waitForExistence(timeout: 5))
        benchPress.tap()

        app.buttons["Save"].tap()

        let routineRow = app.buttons["routineRow-0"]
        XCTAssertTrue(routineRow.waitForExistence(timeout: 5), "Expected the newly created routine to appear in the list")

        routineRow.swipeRight()
        let startButton = app.buttons["startRoutineButton-0"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Expected a leading swipe action to start a workout from this routine")
        startButton.tap()

        XCTAssertTrue(app.textFields["Workout name"].waitForExistence(timeout: 5), "Expected the logger to open")
        XCTAssertEqual(app.textFields["Workout name"].value as? String, "Push Day UI Test", "Expected the logger to be pre-filled with the routine's name")
        XCTAssertTrue(app.staticTexts["Barbell Bench Press"].waitForExistence(timeout: 5), "Expected the routine's exercise to be pre-filled")

        XCTAssertFalse(app.buttons["Start from a routine"].exists, "The workout logger should no longer expose its own routine picker")
    }
}
