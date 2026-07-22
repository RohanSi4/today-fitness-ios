import XCTest

final class Health_TrackerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTodayOpensTheFastWeightLogger() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.buttons["log-weight-button"].tap()
        XCTAssertTrue(app.navigationBars["Morning weight"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Save weight"].exists)
        XCTAssertTrue(app.buttons["Adjust weight by +0.1 pounds"].exists)
    }

    @MainActor
    func testSampleRecapRemainsAvailableFromInsights() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()

        app.tabBars.buttons["Insights"].tap()
        app.buttons["sleep-movement-recap-button"].tap()
        XCTAssertTrue(app.staticTexts["Sample data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sleep details"].exists)

        let recap = app.scrollViews["daily-recap-scroll"]
        XCTAssertTrue(recap.exists)
        recap.swipeUp()
        XCTAssertTrue(app.staticTexts["Movement"].waitForExistence(timeout: 2))
    }
}
