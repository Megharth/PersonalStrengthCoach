import XCTest

class E2ETestBase: XCTestCase {
    var app: XCUIApplication!

    func launch(scenario: String = "empty") {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-test-scenario", scenario]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }

    func tapTab(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let labels = [
            "tab.today": "Today",
            "tab.dashboard": "Dashboard",
            "tab.history": "History",
            "tab.recovery": "Recovery",
            "tab.coach": "Coach",
            "tab.settings": "Settings"
        ]
        let button = app.tabBars.buttons[identifier]
        if button.waitForExistence(timeout: 5) {
            button.tap()
            return
        }
        if let label = labels[identifier], app.tabBars.buttons[label].waitForExistence(timeout: 1) {
            app.tabBars.buttons[label].tap()
            return
        }
        if app.tabBars.buttons["More"].waitForExistence(timeout: 1), let label = labels[identifier] {
            app.tabBars.buttons["More"].tap()
            let moreItem = app.staticTexts[label]
            XCTAssertTrue(moreItem.waitForExistence(timeout: 5), "Expected tab \(identifier) in More.\n\(app.debugDescription)", file: file, line: line)
            moreItem.tap()
            return
        }
        XCTFail("Could not find tab \(identifier).\n\(app.debugDescription)", file: file, line: line)
    }

    func assertTab(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let labels = [
            "tab.today": "Today",
            "tab.dashboard": "Dashboard",
            "tab.history": "History",
            "tab.recovery": "Recovery",
            "tab.coach": "Coach",
            "tab.settings": "Settings"
        ]
        let button = app.tabBars.buttons[identifier]
        let fallback = labels[identifier].map { app.tabBars.buttons[$0] }
        if button.waitForExistence(timeout: 5) || fallback?.waitForExistence(timeout: 1) == true {
            return
        }

        // iOS collapses tabs beyond the visible limit into More.
        let more = app.tabBars.buttons["More"]
        if more.exists {
            more.tap()
        }

        let moreLabel = labels[identifier].map { app.staticTexts[$0] }
        XCTAssertTrue(
            button.waitForExistence(timeout: 5) || fallback?.waitForExistence(timeout: 1) == true || moreLabel?.waitForExistence(timeout: 5) == true,
            "Expected tab \(identifier) to be present.\n\(app.debugDescription)",
            file: file,
            line: line
        )
    }
}
