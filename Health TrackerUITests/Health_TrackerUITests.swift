import XCTest

final class Health_TrackerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSampleRecapShowsCoreSections() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Sample data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sleep details"].exists)

        let recap = app.scrollViews["daily-recap-scroll"]
        XCTAssertTrue(recap.exists)
        recap.swipeUp()
        XCTAssertTrue(app.staticTexts["Movement"].waitForExistence(timeout: 2))
    }
}
