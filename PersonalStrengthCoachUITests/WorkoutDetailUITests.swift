import XCTest

final class WorkoutDetailUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()
    }

    func testWorkoutDetailShowsAllSessionMetricsAndExpandsExercise() throws {
        openSeededWorkout()

        XCTAssertTrue(metric(named: "Volume").waitForExistence(timeout: 5))
        XCTAssertTrue(metric(named: "Duration").exists)
        XCTAssertTrue(metric(named: "Calories").exists)

        let exerciseCard = app.buttons["exerciseCard-Barbell Row"]
        XCTAssertTrue(exerciseCard.waitForExistence(timeout: 5), "Expected the first seeded workout's Barbell Row card")
        XCTAssertEqual(exerciseCard.value as? String, "Collapsed")

        exerciseCard.tap()
        XCTAssertEqual(exerciseCard.value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts["Set 1"].waitForExistence(timeout: 5), "Expected expanded exercise-card set details")

        exerciseCard.tap()
        XCTAssertEqual(exerciseCard.value as? String, "Collapsed")
    }

    func testWorkoutDetailPresentsDeleteConfirmation() throws {
        openSeededWorkout()

        let deleteWorkoutButton = app.buttons["deleteWorkoutButton"]
        XCTAssertTrue(deleteWorkoutButton.waitForExistence(timeout: 5))
        deleteWorkoutButton.tap()

        XCTAssertTrue(app.staticTexts["Delete workout?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete Workout"].exists)
    }

    private func openSeededWorkout() {
        app.tabBars.buttons["Workouts"].tap()
        let firstWorkoutRow = app.buttons["workoutRow-0"]
        XCTAssertTrue(firstWorkoutRow.waitForExistence(timeout: 5), "Expected a seeded workout to be visible in Workouts")
        firstWorkoutRow.tap()
    }

    private func metric(named name: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "workoutDetailMetric-\(name)")
            .firstMatch
    }
}
