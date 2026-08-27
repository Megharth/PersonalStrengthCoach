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
        app.tabBars.buttons["Workouts"].tap()

        let firstWorkoutRow = app.buttons["workoutRow-0"]
        XCTAssertTrue(firstWorkoutRow.waitForExistence(timeout: 5), "Expected a seeded workout to be visible in Workouts")
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
        app.tabBars.buttons["Workouts"].tap()

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

    /// Regression coverage for the Option A "sticky top bar" fix: once the
    /// exercise list is long enough to scroll, the stats strip must stay
    /// docked under the nav bar (fixed position) instead of scrolling away
    /// with the exercise cards beneath it.
    func testSessionStatsStripStaysDockedWhileScrolling() throws {
        app.tabBars.buttons["Workouts"].tap()

        let addWorkoutMenuButton = app.buttons["addWorkoutMenuButton"]
        XCTAssertTrue(addWorkoutMenuButton.waitForExistence(timeout: 5))
        addWorkoutMenuButton.tap()

        let logWorkoutMenuItem = app.buttons["logWorkoutMenuItem"]
        XCTAssertTrue(logWorkoutMenuItem.waitForExistence(timeout: 5))
        logWorkoutMenuItem.tap()

        let statsStrip = app.otherElements["sessionStatsStrip"]
        XCTAssertTrue(statsStrip.waitForExistence(timeout: 5))

        let exerciseNames = [
            "Barbell Bench Press", "Incline Dumbbell Press", "Cable Fly", "Overhead Press"
        ]
        for name in exerciseNames {
            // Each added exercise's first set defaults to expanded, so the list
            // quickly grows taller than one screen -- scroll "Add exercise" back
            // into view (it's virtualized out of the accessibility tree, not just
            // offscreen, once it's far enough below the fold) before tapping it.
            scrollUntilExists(app.buttons["addExerciseButton"])
            app.buttons["addExerciseButton"].tap()
            let exerciseButton = app.buttons[name]
            XCTAssertTrue(exerciseButton.waitForExistence(timeout: 5))
            exerciseButton.tap()
        }

        // Baseline position once the list is actually scrollable (a List's
        // top inset can shift a few points between "fits on screen" and
        // "needs to scroll"), captured before scrolling so it isn't
        // conflated with the empty-list layout at the top of this test.
        let dockedMinY = waitForStableMinY(of: statsStrip)

        // SwiftUI may not bridge the Section header's Text as a .staticText
        // element kind, so match by label across any element type (same
        // reasoning as the stat-strip cells above).
        let lastExerciseHeader = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", exerciseNames.last!)).firstMatch
        scrollUntilExists(lastExerciseHeader)

        XCTAssertTrue(statsStrip.exists, "Expected the stats strip to remain docked rather than scroll away once the exercise list is long enough to scroll")
        XCTAssertEqual(waitForStableMinY(of: statsStrip), dockedMinY, accuracy: 1.0, "Expected the docked stats strip to stay pinned at the same position while the list beneath it scrolls")
    }

    /// Regression coverage for removing the manual workout date field: the
    /// logger infers date/time from the session's start and end instead of
    /// letting the user pick one, on both the new-workout and edit-workout
    /// paths.
    func testWorkoutLoggerDoesNotShowADateField() throws {
        app.tabBars.buttons["Workouts"].tap()

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
        XCTAssertTrue(firstWorkoutRow.waitForExistence(timeout: 5), "Expected a seeded workout to be visible in Workouts")
        firstWorkoutRow.tap()

        let editWorkoutButton = app.buttons["editWorkoutButton"]
        XCTAssertTrue(editWorkoutButton.waitForExistence(timeout: 5))
        editWorkoutButton.tap()

        XCTAssertTrue(app.textFields["Workout name"].waitForExistence(timeout: 5), "Expected the edit-workout logger to appear")
        assertNoDateField()
    }

    /// Regression coverage for persisted exercise-block order: add exercises in
    /// a deliberately non-alphabetical order, save, then verify both the detail
    /// view and edit logger reconstruct the same order.
    func testWorkoutPreservesExerciseEntryOrderThroughDetailAndEdit() throws {
        app.tabBars.buttons["Workouts"].tap()

        let addWorkoutMenuButton = app.buttons["addWorkoutMenuButton"]
        XCTAssertTrue(addWorkoutMenuButton.waitForExistence(timeout: 5))
        addWorkoutMenuButton.tap()
        let logWorkoutMenuItem = app.buttons["logWorkoutMenuItem"]
        XCTAssertTrue(logWorkoutMenuItem.waitForExistence(timeout: 5))
        logWorkoutMenuItem.tap()

        addExercise(named: "Overhead Press")
        markNewestSetComplete()
        addExercise(named: "Barbell Bench Press")
        markNewestSetComplete()
        app.buttons["Save"].tap()

        let newestWorkout = app.buttons["workoutRow-0"]
        XCTAssertTrue(newestWorkout.waitForExistence(timeout: 5), "Expected the newly saved workout to be first in the list")
        newestWorkout.tap()

        assertVerticalOrder(first: "Overhead Press", second: "Bench Press")

        let editWorkoutButton = app.buttons["editWorkoutButton"]
        XCTAssertTrue(editWorkoutButton.waitForExistence(timeout: 5))
        editWorkoutButton.tap()
        assertVerticalOrder(first: "Overhead Press", second: "Barbell Bench Press")
    }

    /// Regression coverage for the workout detail share action. The system share
    /// sheet's available destinations vary by simulator, so assert only that
    /// ShareLink presents a system activity view after the tap.
    func testWorkoutDetailShowsAndPresentsShareAction() throws {
        app.tabBars.buttons["Workouts"].tap()

        let firstWorkoutRow = app.buttons["workoutRow-0"]
        XCTAssertTrue(firstWorkoutRow.waitForExistence(timeout: 5), "Expected a seeded workout to be visible in Workouts")
        firstWorkoutRow.tap()

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
    /// from a caption buried below RPE).
    func testPreviousSetBannerUseButtonFillsFields() throws {
        app.tabBars.buttons["Workouts"].tap()

        // Seeded data has two "Pull Day" workouts with a "Barbell Row" exercise;
        // the most recent one (workoutRow-0) has an older one to reference.
        let firstWorkoutRow = app.buttons["workoutRow-0"]
        XCTAssertTrue(firstWorkoutRow.waitForExistence(timeout: 5), "Expected a seeded workout to be visible in Workouts")
        firstWorkoutRow.tap()

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

    private func addExercise(named name: String) {
        scrollUntilExists(app.buttons["addExerciseButton"])
        app.buttons["addExerciseButton"].tap()

        // Picker options remain in the accessibility tree even while clipped
        // below the sheet viewport, which can make a direct tap a no-op.
        // Search narrows the list to one visible, selectable result instead.
        let searchField = app.searchFields["Search exercises"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Expected the exercise picker search field")
        searchField.tap()
        searchField.typeText(name)

        let exerciseButton = app.buttons[name]
        XCTAssertTrue(exerciseButton.waitForExistence(timeout: 5), "Expected exercise picker option \(name)")
        XCTAssertTrue(exerciseButton.isHittable, "Expected exercise picker option \(name) to be hittable")
        exerciseButton.tap()

        XCTAssertTrue(
            app.navigationBars["Add Exercise"].waitForNonExistence(timeout: 5),
            "Expected the exercise picker to dismiss after selecting \(name)"
        )
        XCTAssertTrue(app.buttons["markCompleteButton-0"].waitForExistence(timeout: 5), "Expected added exercise \(name)'s first set")
    }

    private func markNewestSetComplete() {
        let completeButton = app.buttons["markCompleteButton-0"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5), "Expected the newly added exercise's first set")
        completeButton.tap()
    }

    private func assertVerticalOrder(first: String, second: String) {
        let firstHeader = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", first)).firstMatch
        let secondHeader = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", second)).firstMatch
        XCTAssertTrue(firstHeader.waitForExistence(timeout: 5), "Expected exercise header \(first)")
        XCTAssertTrue(secondHeader.waitForExistence(timeout: 5), "Expected exercise header \(second)")
        XCTAssertLessThan(firstHeader.frame.minY, secondHeader.frame.minY, "Expected \(first) to remain above \(second)")
    }

    private func assertNoDateField() {
        XCTAssertEqual(app.datePickers.count, 0, "The workout logger should not expose a date picker")
        let dateLabel = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Date")).firstMatch
        XCTAssertFalse(dateLabel.exists, "The workout logger should not show a standalone Date field")
    }

    private func scrollUntilExists(_ element: XCUIElement, maxSwipes: Int = 15) {
        var attempts = 0
        while (!element.exists || !element.isHittable) && attempts < maxSwipes {
            scrollListUp()
            attempts += 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: 2), "Expected scrolling to bring the element into view")
        XCTAssertTrue(element.isHittable, "Expected scrolling to make the element hittable")
    }

    /// The dock position can read a stale/mid-animation value for a moment
    /// right after a sheet dismiss or list insert settles; poll until two
    /// consecutive reads agree before trusting it.
    private func waitForStableMinY(of element: XCUIElement, maxAttempts: Int = 10) -> CGFloat {
        var lastValue = element.frame.minY
        for _ in 0..<maxAttempts {
            Thread.sleep(forTimeInterval: 0.2)
            let value = element.frame.minY
            if abs(value - lastValue) < 0.5 {
                return value
            }
            lastValue = value
        }
        return lastValue
    }

    /// A plain `app.swipeUp()` drags from very close to the bottom edge,
    /// which on a presented sheet can be interpreted as the interactive
    /// swipe-to-dismiss gesture instead of a list scroll. Keep both
    /// endpoints well clear of the edges so it always scrolls the List.
    private func scrollListUp() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        // A double-tap selects the numeric token in SwiftUI's text field. This
        // avoids relying on the insertion point, which can start at the leading
        // edge in the simulator and make delete-key replacement prepend digits.
        field.doubleTap()
        field.typeText(text)
    }
}
