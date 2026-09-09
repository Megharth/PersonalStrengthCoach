import XCTest

final class WorkoutDetailUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
        try super.tearDownWithError()
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

    func testWorkoutDetailSyncBiometricsAttachesHealthData() throws {
        openSeededWorkout()

        let syncButton = app.buttons["syncBiometricsWorkoutDetailButton"]
        XCTAssertTrue(syncButton.waitForExistence(timeout: 5))
        syncButton.tap()

        let statusText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Synced")).firstMatch
        XCTAssertTrue(statusText.waitForExistence(timeout: 5))
    }

    func testWorkoutDetailShowsAndPresentsShareAction() throws {
        openSeededWorkout()

        let shareWorkoutButton = app.buttons["shareWorkoutButton"]
        XCTAssertTrue(shareWorkoutButton.waitForExistence(timeout: 5), "Expected the workout detail share action")
        shareWorkoutButton.tap()

        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 5), "Expected ShareLink to present the system share sheet")
    }

    /// Regression coverage for the "Last time" reference banner: editing a set
    /// with a matching prior-session performance must show the previous
    /// weight/reps beside the input fields, and tapping Use must copy those
    /// values into the fields (rather than requiring the user to retype them
    /// from a caption buried below RPE). Relies on the two seeded Pull Day
    /// workouts — workoutRow-0 references workoutRow-3's Barbell Row sets.
    func testPreviousSetBannerUseButtonFillsFields() throws {
        openSeededWorkout()

        let editWorkoutButton = app.buttons["editWorkoutButton"]
        XCTAssertTrue(editWorkoutButton.waitForExistence(timeout: 5))
        editWorkoutButton.tap()

        let setRow = app.buttons.matching(identifier: "setRow-0").firstMatch
        XCTAssertTrue(setRow.waitForExistence(timeout: 5))
        setRow.tap()

        let weightField = app.textFields["weightField-0"]
        let repsField = app.textFields["repsField-0"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        XCTAssertEqual(weightField.value as? String, "90", "Sanity check: this workout's own logged weight before using the previous value")

        let useButton = app.buttons["usePreviousSetButton-0"]
        XCTAssertTrue(useButton.waitForExistence(timeout: 5), "Expected the previous-set reference banner's Use button on the expanded set row")
        useButton.tap()

        XCTAssertEqual(weightField.value as? String, "87.5", "Expected Use to copy the previous session's weight into the field")
        XCTAssertEqual(repsField.value as? String, "8", "Expected Use to copy the previous session's reps into the field")
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
