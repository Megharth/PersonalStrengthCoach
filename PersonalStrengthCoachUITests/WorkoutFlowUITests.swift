import XCTest

final class WorkoutFlowUITests: E2ETestBase {
    private func openLogger() {
        tapTab("tab.history")
        XCTAssertTrue(app.buttons["workoutHistory.addMenu"].waitForExistence(timeout: 5))
        app.buttons["workoutHistory.addMenu"].tap()
        XCTAssertTrue(app.buttons["Log workout"].waitForExistence(timeout: 5))
        app.buttons["Log workout"].tap()
        XCTAssertTrue(app.navigationBars["Log Workout"].waitForExistence(timeout: 5))
    }

    private func addBenchPress() {
        XCTAssertTrue(app.buttons["workout.addExercise"].waitForExistence(timeout: 5))
        app.buttons["workout.addExercise"].tap()
        let exercise = app.buttons["exercisePicker.exercise.Barbell Bench Press"]
        XCTAssertTrue(exercise.waitForExistence(timeout: 5))
        exercise.tap()
    }

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
        openLogger()

        app.buttons["workout.save"].tap()

        XCTAssertTrue(app.alerts["Add an exercise first"].waitForExistence(timeout: 5))
    }

    func testLoggerShowsSetDetailsAndSessionStatus() {
        launch()
        openLogger()
        addBenchPress()

        XCTAssertTrue(app.staticTexts["Active workout"].waitForExistence(timeout: 5))
        let details = app.buttons["workout.set.1.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()

        XCTAssertTrue(app.textFields["workout.set.1.rpe"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["RPE is optional effort from 0–10; each half point is about one rep in reserve."].waitForExistence(timeout: 5))
    }

    func testLoggerDeletesSetWithUndoRecovery() {
        launch()
        openLogger()
        addBenchPress()

        let delete = app.buttons["workout.set.1.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        XCTAssertTrue(app.staticTexts["Set deleted"].waitForExistence(timeout: 5))
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
    }

    func testCompletingOneSetCommitsOnlyThatSet() {
        launch()
        openLogger()
        addBenchPress()

        let addSet = app.buttons["Add set"]
        XCTAssertTrue(addSet.waitForExistence(timeout: 5))
        addSet.tap()

        let firstWeight = app.textFields["Weight for set 1, in kg"]
        let secondWeight = app.textFields["Weight for set 2, in kg"]
        XCTAssertTrue(firstWeight.waitForExistence(timeout: 5))
        XCTAssertTrue(secondWeight.waitForExistence(timeout: 5))

        firstWeight.tap()
        firstWeight.typeText("72.5")
        secondWeight.tap()
        secondWeight.typeText("81")

        app.buttons["workout.set.1.complete"].tap()

        XCTAssertEqual(firstWeight.value as? String, "72.5")
        XCTAssertEqual(secondWeight.value as? String, "81")
    }
}
