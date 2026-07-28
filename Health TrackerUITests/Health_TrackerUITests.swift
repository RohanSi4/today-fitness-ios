import XCTest

final class Health_TrackerUITests: XCTestCase {
    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false

        // Device orientation is simulator state, not process state: it outlives
        // the test run that set it. `Health_TrackerUITestsLaunchTests` has
        // `runsForEachTargetApplicationUIConfiguration = true`, which includes
        // landscape, and the app declares no supported orientations, so it
        // happily rotates. The run therefore *ends* in landscape and poisons the
        // next one - four tests here failed on a 956x440 window with the
        // controls they tap pushed below the fold, having passed minutes before
        // on identical code.
        //
        // These screens are designed portrait, so pinning it is both the honest
        // precondition and the thing that makes the suite reproducible.
        XCUIDevice.shared.orientation = .portrait
    }

    /// The app is portrait only, declared in build settings rather than at
    /// runtime, which means nothing in the Swift sources mentions it and a stray
    /// edit to the project file would go unnoticed. This is the guard.
    ///
    /// It is also the root cause of the flakiness the `setUpWithError` note
    /// describes: while landscape was allowed, the launch test's rotation
    /// outlived the run and broke the next one.
    @MainActor
    func testTheAppStaysPortraitWhenTheDeviceIsRotated() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        let portrait = app.windows.firstMatch.frame
        XCTAssertGreaterThan(portrait.height, portrait.width, "did not start portrait")

        defer { XCUIDevice.shared.orientation = .portrait }
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            // The rotation is animated and the device may honour it even when the
            // app does not, so settle before measuring the app's own window.
            Thread.sleep(forTimeInterval: 1.5)

            let frame = app.windows.firstMatch.frame
            XCTAssertGreaterThan(
                frame.height,
                frame.width,
                "app rotated to \(orientation.rawValue); it is meant to be portrait only"
            )
        }
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
    func testPostRunHoldWaitsForPlayAndCanPauseOrOpenRoutineWheel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useMockData", "true"]
        app.launch()

        let stretches = app.buttons["stretches-button"]
        XCTAssertTrue(stretches.waitForExistence(timeout: 5))
        stretches.tap()

        let postRun = app.segmentedControls.buttons["Post-run"]
        XCTAssertTrue(postRun.waitForExistence(timeout: 2))
        postRun.tap()
        app.buttons["start-stretch-routine"].tap()

        let timerButton = app.buttons["stretch-timer-button"]
        XCTAssertTrue(timerButton.waitForExistence(timeout: 2))
        XCTAssertEqual(timerButton.label, "Start 30-second hold")
        XCTAssertTrue(app.staticTexts["Ready when you are"].exists)

        timerButton.tap()
        XCTAssertEqual(timerButton.label, "Pause")

        app.buttons["stretch-step-picker-button"].tap()
        XCTAssertTrue(app.navigationBars["Routine wheel"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.pickers["stretch-step-picker"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertEqual(timerButton.label, "Resume hold")

        timerButton.tap()
        XCTAssertEqual(timerButton.label, "Pause")
        timerButton.tap()
        XCTAssertEqual(timerButton.label, "Resume hold")
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
