import XCTest

final class NavigationUITests: E2ETestBase {
    func testEmptyLaunchShowsAllTabs() {
        launch()
        for tab in ["tab.today", "tab.dashboard", "tab.history", "tab.recovery", "tab.coach", "tab.settings"] {
            assertTab(tab)
        }
    }

    func testHistoryScenarioShowsHistoryTab() {
        launch(scenario: "history")
        let historyTab = app.tabBars.buttons["tab.history"]
        if historyTab.waitForExistence(timeout: 5) {
            historyTab.tap()
        } else if app.tabBars.buttons["History"].waitForExistence(timeout: 5) {
            app.tabBars.buttons["History"].tap()
        } else {
            app.tabBars.buttons["More"].tap()
            app.staticTexts["History"].tap()
        }
        XCTAssertTrue(app.staticTexts["Fixture Pull"].waitForExistence(timeout: 5))
    }
}
