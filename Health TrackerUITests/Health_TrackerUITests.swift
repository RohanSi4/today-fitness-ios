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

    @MainActor
    func testWeeklySnapshotOpensFromToday() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()

        let card = app.buttons["weekly-snapshot-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars["This week"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["weekly-snapshot-table"].exists)
    }

    @MainActor
    func testStretchRoutineCanBeBrowsedAndGuided() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()

        let stretches = app.buttons["stretches-button"]
        XCTAssertTrue(stretches.waitForExistence(timeout: 5))
        stretches.tap()

        XCTAssertTrue(app.navigationBars["Run stretches"].waitForExistence(timeout: 2))
        let firstCard = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Butt kickers"))
            .firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 2))
        firstCard.tap()
        XCTAssertTrue((firstCard.value as? String)?.contains("Expanded") == true)

        let start = app.buttons["start-stretch-routine"]
        XCTAssertTrue(start.exists)
        start.tap()

        XCTAssertTrue(app.scrollViews["stretch-session-scroll"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Butt kickers"].exists)
        app.buttons["complete-stretch-step"].tap()
        XCTAssertTrue(app.staticTexts["Frankensteins"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testActiveWorkoutCanCloseAndResumeWithoutBeingDiscarded() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()

        let resume = app.buttons["resume-workout-button"]
        if resume.waitForExistence(timeout: 2) {
            resume.tap()
        } else {
            let start = app.buttons["start-workout-button"]
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            start.tap()
            let upper = app.buttons["start-upper-workout"]
            XCTAssertTrue(upper.waitForExistence(timeout: 2))
            upper.tap()
        }

        let close = app.buttons["close-workout-button"]
        XCTAssertTrue(close.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["workout-options-menu"].exists)
        close.tap()

        XCTAssertTrue(resume.waitForExistence(timeout: 2))
        resume.tap()
        XCTAssertTrue(app.buttons["close-workout-button"].waitForExistence(timeout: 2))
    }
}
