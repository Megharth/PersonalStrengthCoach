import XCTest

final class WorkoutFlowUITests: E2ETestBase {
    func testEmptyHistoryOffersWorkoutEntry() {
        launch()
        assertTab("tab.history")
        tapTab("tab.history")

        XCTAssertTrue(app.navigationBars["Workout History"].waitForExistence(timeout: 5))
        let addMenu = app.buttons["workoutHistory.addMenu"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 5))
        addMenu.tap()

        let logWorkout = app.buttons["Log workout"]
        XCTAssertTrue(logWorkout.waitForExistence(timeout: 5))
        logWorkout.tap()

        XCTAssertTrue(app.navigationBars["Log Workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["workout.addExercise"].waitForExistence(timeout: 5))
    }

    func testLoggerRequiresExerciseBeforeSaving() {
        launch()
        tapTab("tab.history")
        app.buttons["workoutHistory.addMenu"].tap()
        app.buttons["Log workout"].tap()

        app.buttons["workout.save"].tap()

        XCTAssertTrue(app.alerts["Add an exercise first"].waitForExistence(timeout: 5))
    }
}
