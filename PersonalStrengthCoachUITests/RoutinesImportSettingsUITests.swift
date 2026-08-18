import XCTest

final class RoutinesImportSettingsUITests: E2ETestBase {
    func testHistoryMenuOpensRoutinesAndRoutineEditor() {
        launch()
        tapTab("tab.history")
        app.buttons["workoutHistory.addMenu"].tap()
        XCTAssertTrue(app.buttons["Routines"].waitForExistence(timeout: 5))
        app.buttons["Routines"].tap()

        XCTAssertTrue(app.navigationBars["Routines"].waitForExistence(timeout: 5))
        app.buttons["routines.new"].tap()
        XCTAssertTrue(app.navigationBars["New Routine"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Routine name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routine.save"].waitForExistence(timeout: 5))
    }

    func testHistoryMenuOpensStrongImport() {
        launch()
        tapTab("tab.history")
        app.buttons["workoutHistory.addMenu"].tap()
        XCTAssertTrue(app.buttons["Import from Strong"].waitForExistence(timeout: 5))
        app.buttons["Import from Strong"].tap()

        XCTAssertTrue(app.navigationBars["Import from Strong"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose file"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Paste export"].waitForExistence(timeout: 5))
    }

    func testSettingsShowsWeightUnitPicker() {
        launch()
        tapTab("tab.settings")

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Units"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weight unit"].waitForExistence(timeout: 5))
    }

    func testRecoveryScenarioShowsRecoveryScreen() {
        launch(scenario: "recovery")
        tapTab("tab.recovery")

        XCTAssertTrue(app.staticTexts["Recovery"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Muscle recovery"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weekly averages"].waitForExistence(timeout: 5))
    }
}
